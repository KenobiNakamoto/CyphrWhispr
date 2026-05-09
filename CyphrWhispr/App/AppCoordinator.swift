import Foundation
import AppKit
import Combine
import QuartzCore  // CACurrentMediaTime() — monotonic clock for the install rim timer

enum AppState: Equatable {
    case idle
    case loadingModel
    /// Hotkey pressed but pill is mid-spawn (and/or whisper still warming).
    /// Audio capture has started; samples accumulate in `spawnBuffer`
    /// until both the spawn animation completes AND `whisper.warmUp()`
    /// has resolved, at which point we drain into `whisper.append(...)`
    /// and advance to `.streaming`.
    case spawning
    case armed
    case streaming
    case finalizing
    case injecting
    case error(String)
}

@MainActor
final class AppCoordinator {
    private(set) var state: AppState = .idle {
        didSet { stateSubject.send(state) }
    }

    let stateSubject = PassthroughSubject<AppState, Never>()

    private let statusItem = StatusItemController()
    private let hotkey = HotkeyManager()
    private let audio = AudioCaptureEngine()
    private let pill = PillWindowController()
    private let whisper: WhisperEngine
    private let injector = ClipboardPasteInjector()
    private let prefs: PreferencesStore
    /// Apple Foundation Models cleanup. Stateless — one shared instance used
    /// for every commit. Whether it actually runs is gated by
    /// `prefs.polishEnabled` AND the cleaner's own availability check (which
    /// confirms we're on macOS 26+, Apple Intelligence is enabled, etc.).
    private let cleaner: TranscriptionCleaner = FoundationModelsCleaner()
    /// Hard cap on how long we'll wait for the cleanup pass before giving
    /// up and pasting the raw transcript. Keeps the UX from hanging if the
    /// model takes a coffee break or the user dictated something unusually
    /// long.
    private static let polishTimeout: TimeInterval = 3.0

    private var cancellables = Set<AnyCancellable>()
    private var streamConsumer: Task<Void, Never>?
    /// In-flight model switch task; we cancel an earlier switch if the user
    /// rapid-fires through a few options in Settings.
    private var modelSwitchTask: Task<Void, Never>?
    /// In-flight whisper warm-up task during the spawn window. Cancelled
    /// when the user releases the hotkey mid-spawn (so we don't try to
    /// drain into a stream that never starts).
    private var whisperWarmAwaiter: Task<Void, Never>?
    /// Set when `pill.onSpawnComplete` fires for the current session.
    private var spawnAnimationDone: Bool = false
    /// Set when `whisper.warmUp()` resolves for the current session.
    private var whisperWarmDone: Bool = false
    /// Audio captured during the spawn window. Drained into
    /// `whisper.append(...)` the moment streaming begins.
    private var spawnBuffer: [Float] = []

    // MARK: - Install-path state
    //
    // The install animation only runs when the user hits the hotkey while
    // the model is still warming up (i.e. `state == .loadingModel` at press
    // time). Distinguishing this from the cinematic spawn flow needs a
    // small parallel state machine — different completion gating, different
    // pill entry point, different rim driver.
    //
    // The pill goes through .installSpawning → .installCompiling →
    // .installOutro → .armed in sequence. The coordinator's `state` stays
    // at `.spawning` throughout (audio is buffering, no streaming yet) and
    // only advances to `.streaming` when `installOutroDone` flips.

    /// True when the current hotkey session entered via the install path.
    /// Resets to false at session end. Drives the gating in
    /// `maybeBeginStreaming()` and the cleanup in error/cancel paths.
    private var installPathActive: Bool = false
    /// Set when `pill.onInstallIntroComplete` fires. Used together with
    /// `whisperWarmDone` so that the outro only fires once BOTH the
    /// intro animation has finished AND warm-up has resolved — avoids
    /// the race where a fast warm-up triggers the outro mid-intro and
    /// the pill phase jumps visibly.
    private var installIntroDone: Bool = false
    /// Set when `pill.onInstallOutroComplete` fires. Sole gate that
    /// promotes the install path from `.spawning` → `.streaming`.
    private var installOutroDone: Bool = false
    /// True once the install animation has run to completion at least
    /// once in this app session (i.e. outro fired). The first hotkey
    /// press of a session always uses the install path regardless of
    /// warm-up state — that's the canonical "app start" choreography.
    /// Subsequent presses fall through to the cinematic spawn (or no
    /// animation, depending on PillWindowController.show()'s session
    /// memory). Resets on model switch so a new model gets its install
    /// animation again.
    private var hasPlayedSessionFirstPress: Bool = false
    /// Drives `pill.setInstallProgress(_:)` from the install intro
    /// completion until either (a) warm-up resolves and we snap to 1.0
    /// and play the outro, or (b) 30 s passes and the rim sits visually
    /// full while we keep waiting for warm-up.
    private var installRimTask: Task<Void, Never>?

    /// Wall-clock target for a full rim sweep when we don't know how
    /// long the model will actually take. 30 s comfortably covers the
    /// typical 30–60 s Apple Silicon Whisper model compile while staying
    /// short enough that the user doesn't sit through "blank rim" stretches
    /// on slow disks. If warm-up resolves earlier we snap to 1.0; if it
    /// takes longer, the rim holds at 1.0.
    private static let installRimSweepDuration: TimeInterval = 30.0

    /// Quick rim-sweep duration used when warm-up has already resolved
    /// by the time the intro animation finishes (cached model, fast
    /// disk). Long enough that the rim is visibly a sweep — not a snap
    /// — so the install choreography reads as deliberate. Short enough
    /// that the user isn't waiting on a fake progress bar.
    private static let installRimQuickSweepDuration: TimeInterval = 1.0

    init(prefs: PreferencesStore = .shared) {
        self.prefs = prefs
        // Pass the persisted language preference into the backend at
        // construction so the very first hotkey press uses the right
        // language, not the backend's "en" default. `effectiveLanguageCode`
        // resolves the picker choice against the model's English-only
        // constraint — see PreferencesStore for the rule.
        self.whisper = WhisperKitBackend(
            modelName: prefs.activeModelID,
            languageCode: prefs.effectiveLanguageCode
        )
    }

    /// Serial queue for live typing so paste/backspace cycles don't pile up on
    /// the main thread or interleave with each other.
    private let typingQueue = DispatchQueue(label: "com.cyphr.whispr.typing")

    /// Tracks the text we've already typed at the user's cursor so we can
    /// compute a minimal diff against each new partial transcript.
    /// Only mutated on `typingQueue`.
    private var typedSoFar: String = ""

    /// Captures the user's clipboard once at the start of a session so we can
    /// freely use the clipboard for live typing in between, and restore it on
    /// completion.
    /// Only mutated on `typingQueue`.
    private var sessionClipboard: PasteboardSnapshot?

    func start() {
        statusItem.install()
        statusItem.onQuit = { NSApp.terminate(nil) }

        hotkey.onPress = { [weak self] in self?.handleHotkeyPress() }
        hotkey.onRelease = { [weak self] in self?.handleHotkeyRelease() }
        hotkey.install()

        audio.onLevel = { [weak self] level in
            self?.pill.updateLevel(level)
        }
        audio.onSamples = { [weak self] samples in
            self?.feed(samples: samples)
        }

        // The pill fires this when its cinematic spawn animation finishes
        // (or immediately on subsequent shows in the same session). It's
        // one half of the precondition for advancing to `.streaming`; the
        // other half is whisper.warmUp resolving.
        pill.onSpawnComplete = { [weak self] in
            guard let self else { return }
            self.spawnAnimationDone = true
            self.maybeBeginStreaming()
        }

        // Install path: intro complete → either start the long rim-progress
        // driver (if warm-up still pending) or do a quick 1s sweep + outro
        // (if warm-up already finished during the intro). Either way mark
        // `installIntroDone` so the warm-up callback can decide whether
        // it's racing the intro or showing up after.
        pill.onInstallIntroComplete = { [weak self] in
            guard let self else { return }
            self.installIntroDone = true
            if self.whisperWarmDone {
                // Cached-model fast path — warm-up beat the intro. Run a
                // brief rim sweep so the user still sees the compile
                // phase as a deliberate beat, then auto-fire the outro.
                self.startInstallRimSweep(over: Self.installRimQuickSweepDuration,
                                          thenPlayOutro: true)
            } else {
                // Cold-model slow path — drive the full 30s rim while we
                // wait for `whisper.warmUp()`. The warm-up callback will
                // cancel this and play the outro when it resolves.
                self.startInstallRimSweep(over: Self.installRimSweepDuration,
                                          thenPlayOutro: false)
            }
        }

        // Install path: outro complete → start streaming. We only honour
        // this when we're still in `.spawning` (early hotkey release would
        // have already moved us past .spawning, in which case the outro
        // we triggered before the user gave up should just no-op here).
        // Mark `hasPlayedSessionFirstPress` here so the install animation
        // is treated as "done" only once we've actually finished it; if
        // the user cancels mid-spawn, the next press still plays it.
        pill.onInstallOutroComplete = { [weak self] in
            guard let self else { return }
            guard self.installPathActive else { return }
            self.installOutroDone = true
            self.hasPlayedSessionFirstPress = true
            self.maybeBeginStreaming()
        }

        stateSubject
            .sink { [weak self] state in self?.statusItem.update(for: state) }
            .store(in: &cancellables)

        // Pre-warm WhisperKit in the background — first model compile is 30-90s
        // on Apple Silicon. We don't want the first hotkey press to look frozen.
        state = .loadingModel
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.whisper.warmUp()
                await MainActor.run { self.state = .idle }
            } catch {
                await MainActor.run {
                    self.state = .error("Model load failed: \(error.localizedDescription)")
                    self.scheduleReturnToIdle()
                }
            }
        }

        // Prompt for Accessibility on first launch so the user isn't surprised
        // when paste injection fails.
        _ = ClipboardPasteInjector.ensureAccessibilityTrusted(prompt: true)

        // Re-warm whenever the user picks a different model in Settings.
        // .dropFirst skips the initial value (already used in the WhisperKitBackend init).
        prefs.$activeModelID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newID in self?.switchModel(to: newID) }
            .store(in: &cancellables)

        // Push language-preference changes into the backend whenever the user
        // toggles the picker in Settings (or when the active model changes
        // and `effectiveLanguageCode` flips because we moved between an .en
        // and a multilingual variant). The engine reads its language code
        // once at `startStream()`, so propagating eagerly means the next
        // hotkey press picks up the new value with no race window.
        Publishers.CombineLatest(prefs.$selectedLanguageCode,
                                 prefs.$activeModelID)
            .compactMap { [weak prefs] _, _ in prefs?.effectiveLanguageCode }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] code in
                guard let self else { return }
                Task { await self.whisper.setLanguageCode(code) }
            }
            .store(in: &cancellables)
    }

    /// Hot-swap the active Whisper model. Cancels any active session and any
    /// previous in-flight switch. Safe to call from any thread; we hop to the
    /// main actor to mutate state.
    func switchModel(to modelID: String) {
        modelSwitchTask?.cancel()
        // If the user is mid-recording, abandon the session — model changes
        // shouldn't silently corrupt the in-flight transcription.
        if case .streaming = state {
            audio.stop()
            endSession(restoreClipboard: true)
        } else if case .spawning = state {
            // User picked a different model while still mid-spawn (held the
            // hotkey before opening Settings, or a programmatic switch fired).
            // Treat exactly like an early hotkey release: cancel the warm-up
            // awaiter that was racing against the OLD model's load, drop the
            // partial audio buffer, stop the mic, hide the pill, restore the
            // clipboard. The new model will pre-warm in the background as
            // usual; the pill replay flag was already armed by
            // PreferencesStore.activeModelDidChange.
            //
            // Same install-path cleanup as the hotkey-release branch — kill
            // the rim timer and reset both gating flags so the next session
            // doesn't inherit stale "outro already done" state.
            whisperWarmAwaiter?.cancel()
            whisperWarmAwaiter = nil
            installRimTask?.cancel()
            installRimTask = nil
            spawnAnimationDone = false
            whisperWarmDone = false
            installIntroDone = false
            installOutroDone = false
            installPathActive = false
            spawnBuffer.removeAll(keepingCapacity: false)
            audio.stop()
            endSession(restoreClipboard: true)
        }
        // New model = new compile potentially required = let the install
        // animation play again on the next first-press.
        hasPlayedSessionFirstPress = false
        state = .loadingModel
        modelSwitchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.whisper.loadModel(named: modelID)
                await MainActor.run { self.state = .idle }
            } catch {
                await MainActor.run {
                    self.state = .error("Model load failed: \(error.localizedDescription)")
                    self.scheduleReturnToIdle()
                }
            }
        }
    }

    func shutdown() {
        streamConsumer?.cancel()
        audio.stop()
        pill.hide()
        statusItem.remove()
    }

    // MARK: - Hotkey

    private func handleHotkeyPress() {
        // Accept presses during .idle AND during the brief .loadingModel
        // window after launch — the pre-warm is happening in the background
        // and we now have a "spawning" state + spawn buffer to bridge the gap.
        guard state == .idle || state == .loadingModel else { return }

        guard ClipboardPasteInjector.ensureAccessibilityTrusted(prompt: true) else {
            state = .error("Accessibility permission required. Toggle CyphrWhispr OFF then ON in System Settings → Privacy & Security → Accessibility.")
            scheduleReturnToIdle()
            return
        }

        // The install animation is the canonical "app first start"
        // choreography — it plays on the first hotkey press of every
        // session, regardless of whether warm-up is still in flight.
        // The rim sweep adapts: if warm-up is fast (cached model), we
        // do a quick 1s sweep so the compile phase still reads as
        // deliberate; if it's slow (fresh model, first compile),
        // the full 30s sweep with real progress applies.
        // Subsequent presses in the same session fall through to
        // `pill.show()` (cinematic spawn / no animation).
        // Decision is frozen for the press via `installPathActive` —
        // flipping mid-session would confuse the pill choreography.
        let useInstallPath = (state == .loadingModel) || !hasPlayedSessionFirstPress
        installPathActive = useInstallPath

        // Enter spawning state — audio capture starts immediately and
        // samples buffer locally. `state` stays `.spawning` regardless of
        // path; the pill phase carries the visual distinction.
        state = .spawning
        spawnBuffer.removeAll(keepingCapacity: true)
        if useInstallPath {
            pill.showInstall()
        } else {
            pill.show()
        }

        do {
            try audio.start()
        } catch {
            state = .error("Microphone unavailable: \(error.localizedDescription)")
            pill.hide()
            scheduleReturnToIdle()
            return
        }

        typingQueue.async { [weak self] in
            guard let self else { return }
            self.sessionClipboard = PasteboardSnapshot.capture()
            self.typedSoFar = ""
        }

        // Reset readiness flags for the chosen path. spawnAnimationDone +
        // whisperWarmDone gate the cinematic path; installIntroDone +
        // installOutroDone gate the install path. We always reset all of
        // them so cancelled-and-retried sessions start from a clean slate.
        spawnAnimationDone = false
        whisperWarmDone = false
        installIntroDone = false
        installOutroDone = false

        whisperWarmAwaiter?.cancel()
        whisperWarmAwaiter = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.whisper.warmUp()
            } catch {
                await MainActor.run {
                    self.state = .error("Model load failed: \(error.localizedDescription)")
                    self.endSession(restoreClipboard: true)
                }
                return
            }
            await MainActor.run {
                self.whisperWarmDone = true
                if self.installPathActive {
                    // Install path: only fire the outro if the intro has
                    // already completed. If warm-up beat the intro
                    // (cached/fast model), we silently set the flag and
                    // let `pill.onInstallIntroComplete` pick up the
                    // shortcut — running a quick 1s rim sweep + outro.
                    // Without this guard, a fast warm-up would yank the
                    // pill into `.installOutro` mid-intro and look janky.
                    guard self.installIntroDone else { return }
                    self.installRimTask?.cancel()
                    self.installRimTask = nil
                    self.pill.setInstallProgress(1.0)
                    self.pill.playInstallOutro()
                } else {
                    // Cinematic path: try to advance state; the spawn
                    // animation completing is the other half of the gate.
                    self.maybeBeginStreaming()
                }
            }
        }
    }

    /// Drives the rim from 0 → 1 over `duration` seconds once the install
    /// intro animation completes. Two modes:
    ///
    ///   • **Long sweep** (`thenPlayOutro: false`) — used when warm-up is
    ///     still in flight. Cancelled and replaced by a snap to 1.0 the
    ///     moment `whisper.warmUp()` resolves; the warm-up callback
    ///     plays the outro. If the sweep reaches the end before warm-up,
    ///     the rim sits visually full and we keep waiting.
    ///
    ///   • **Quick sweep** (`thenPlayOutro: true`) — used when warm-up
    ///     already resolved during the intro (cached-model fast path).
    ///     The sweep runs to completion uninterrupted and auto-fires
    ///     the outro when it finishes, so the user sees a deliberate
    ///     intro → quick compile → outro sequence rather than the pill
    ///     skipping straight to the outro.
    ///
    /// 60Hz tick — same cadence WaveformView uses for live audio bars,
    /// chosen because it matches the screen refresh rate on M1+ Macs.
    private func startInstallRimSweep(over duration: TimeInterval = installRimSweepDuration,
                                      thenPlayOutro: Bool = false) {
        installRimTask?.cancel()
        installRimTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let start = CACurrentMediaTime()
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - start
                let p = min(1.0, elapsed / duration)
                self.pill.setInstallProgress(p)
                if p >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60Hz
            }
            if !Task.isCancelled && thenPlayOutro {
                self.pill.playInstallOutro()
            }
        }
    }

    /// Called from up to three places, gated by which path this session
    /// took. Idempotent — re-entering after `.streaming` is a no-op.
    ///
    /// Cinematic spawn path (default):
    ///   • `pill.onSpawnComplete` flips `spawnAnimationDone`
    ///   • the warm-up Task flips `whisperWarmDone`
    ///   • whichever arrives second triggers streaming
    ///
    /// Install path (active only when the user pressed during
    /// `.loadingModel`):
    ///   • the warm-up Task triggers the outro animation when it resolves
    ///   • `pill.onInstallOutroComplete` flips `installOutroDone`
    ///   • that single signal triggers streaming
    private func maybeBeginStreaming() {
        guard state == .spawning else { return }
        if installPathActive {
            guard installOutroDone else { return }
        } else {
            guard spawnAnimationDone && whisperWarmDone else { return }
        }
        beginStreaming()
    }

    /// Open a streaming session, drain any buffered audio, and transition to
    /// `.streaming`. Caller MUST be on the main actor and MUST have verified
    /// `state == .spawning` (i.e. the user hasn't released the hotkey yet).
    private func beginStreaming() {
        streamConsumer = Task { [weak self] in
            guard let self else { return }
            let stream = await self.whisper.startStream()
            for await update in stream {
                self.applyTranscriptUpdate(update.text)
            }
        }
        state = .streaming

        // Drain whatever audio piled up during the spawn window.
        let drained = spawnBuffer
        spawnBuffer.removeAll(keepingCapacity: true)
        if !drained.isEmpty {
            Task { [whisper] in
                await whisper.append(samples: drained)
            }
        }
    }

    private func handleHotkeyRelease() {
        // Release during .spawning is valid — user gave up before whisper
        // was ready. Cancel cleanly: stop audio, drop the buffer, hide
        // the pill, restore clipboard. Covers BOTH cinematic spawn and
        // install paths; the install path adds a rim timer to cancel and
        // a couple of extra flags to reset.
        if state == .spawning {
            whisperWarmAwaiter?.cancel()
            whisperWarmAwaiter = nil
            installRimTask?.cancel()
            installRimTask = nil
            spawnAnimationDone = false
            whisperWarmDone = false
            installIntroDone = false
            installOutroDone = false
            installPathActive = false
            spawnBuffer.removeAll(keepingCapacity: false)
            audio.stop()
            // pill.hide() inside endSession calls viewModel.cancelInstall(),
            // so any in-flight intro/outro on the pill side gets killed too.
            endSession(restoreClipboard: true)
            return
        }

        guard state == .streaming else { return }
        state = .finalizing
        // Drive the pill into its "processing / thinking" animation while the
        // model finalises the transcription. The pill itself decides what that
        // looks like (currently a left-to-right travelling wave on the bars).
        pill.setPhase(.processing)
        audio.stop()

        Task { [weak self] in
            guard let self else { return }
            do {
                let finalRaw = try await self.whisper.finishStream()
                // Optional cleanup pass before we type the final commit.
                // `polish(...)` returns the raw text on any failure mode
                // (disabled, unavailable, timeout, model rejection) so the
                // user always gets _something_ pasted.
                let finalText = await self.polish(rawTranscript: finalRaw)
                await MainActor.run { self.commitFinalText(finalText) }
            } catch {
                await MainActor.run {
                    self.state = .error("Transcription failed: \(error.localizedDescription)")
                    self.endSession(restoreClipboard: true)
                }
            }
        }
    }

    /// Optional Apple Foundation Models cleanup pass. Sits between
    /// `whisper.finishStream()` and `commitFinalText(...)` and folds the LM's
    /// output into the existing typing pipeline.
    ///
    /// Behavioural contract:
    ///   • If polish is OFF in settings → return raw verbatim, no LM call.
    ///   • If polish is ON but the OS doesn't support it → return raw, log it.
    ///   • If the LM call times out / errors / returns mangled text → return
    ///     raw. We always paste _something_; polish is opportunistic.
    ///   • If the cleaner says the input was empty silence → return "" so the
    ///     typeDiff path backspaces out the streamed partials and leaves no
    ///     trace. This is the only case where we paste less than raw.
    ///
    /// The pill stays in `.processing` (travelling-wave bars) for the whole
    /// cleanup window. A dedicated polish-state pill animation can come later;
    /// for now the user sees "still working" until the diff types.
    private func polish(rawTranscript raw: String) async -> String {
        guard prefs.polishEnabled else { return raw }

        let outcome = await cleaner.clean(
            raw,
            prompt: prefs.effectivePolishPrompt,
            timeout: Self.polishTimeout
        )

        switch outcome {
        case .cleaned(let text):
            return text
        case .empty:
            // Backspace partials, type nothing. Silence dictation leaves no trace.
            return ""
        case .skipped(let reason):
            NSLog("[CyphrWhispr] Polish skipped: \(reason)")
            return raw
        case .rejected(let reason):
            NSLog("[CyphrWhispr] Polish rejected: \(reason)")
            return raw
        }
    }

    private func feed(samples: [Float]) {
        switch state {
        case .streaming:
            Task { [whisper] in
                await whisper.append(samples: samples)
            }
        case .spawning:
            // Buffer locally — we'll drain into whisper.append once the spawn
            // animation completes AND whisper.warmUp() resolves.
            spawnBuffer.append(contentsOf: samples)
        default:
            return
        }
    }

    // MARK: - Live typing

    private func applyTranscriptUpdate(_ rawText: String) {
        typingQueue.async { [weak self] in
            guard let self else { return }
            let cleaned = TranscriptSanitizer.clean(rawText)
            self.typeDiff(target: cleaned)
        }
    }

    /// Brings the typed text in the user's field to match `target` by sending
    /// the smallest possible backspace + paste/keystroke sequence. Must be
    /// called on `typingQueue`.
    ///
    /// `committingFinal: true` switches the suffix-write path from clipboard ⌘V
    /// to direct Unicode keystrokes via `injector.typeUnicode(_:)`. This
    /// matters at session end: the partial-transcript path uses `pasteWithoutRestore`
    /// for speed, but a clipboard ⌘V is racy with the subsequent
    /// clipboard-restore in `finalizeSession()` — slow apps can read the
    /// (already-restored) old clipboard and paste THAT instead of the
    /// transcription. Direct Unicode keystrokes carry the text in the event
    /// payload itself, eliminating the race entirely. We accept the small
    /// per-character cost (~8ms × delta-length) because the final commit's
    /// delta is typically tiny — last partial → final usually differs by
    /// punctuation or a single revised word.
    private func typeDiff(target: String, committingFinal: Bool = false) {
        guard target != typedSoFar else { return }

        let commonPrefix = typedSoFar.commonPrefix(with: target)
        let backspaceCount = typedSoFar.count - commonPrefix.count
        let suffix = String(target.dropFirst(commonPrefix.count))

        do {
            if backspaceCount > 0 {
                try injector.sendBackspaces(backspaceCount)
            }
            if !suffix.isEmpty {
                if committingFinal {
                    try injector.typeUnicode(suffix)
                } else {
                    try injector.pasteWithoutRestore(suffix)
                }
            }
            typedSoFar = target
        } catch let error as PasteInjectionError {
            NSLog("[CyphrWhispr] Paste failed: \(error.localizedDescription)")
            // Surface the failure to the menu bar so the user gets feedback
            // instead of a silent dead pill.
            DispatchQueue.main.async { [weak self] in
                self?.state = .error(error.localizedDescription)
            }
        } catch {
            NSLog("[CyphrWhispr] Unexpected paste error: \(error)")
        }
    }

    private func commitFinalText(_ text: String) {
        streamConsumer?.cancel()
        streamConsumer = nil

        let cleaned = TranscriptSanitizer.clean(text)
        typingQueue.async { [weak self] in
            guard let self else { return }
            // committingFinal: true → final delta is keystroke-typed, not
            // ⌘V-pasted, so the subsequent clipboard restore in
            // finalizeSession() can't race with a still-pending paste event.
            self.typeDiff(target: cleaned, committingFinal: true)
            self.finalizeSession()
        }

        state = .injecting
    }

    /// Restore the user's original clipboard, drop the typing-state, and bounce
    /// back to idle. Called from `typingQueue`.
    ///
    /// The sleep before restore is critical: even though the FINAL commit now
    /// goes through `typeUnicode` (no clipboard, no race there), the LAST
    /// PARTIAL of the streaming session was still a clipboard ⌘V — and the
    /// receiving app may not have consumed that paste event yet. Restore too
    /// early and slow apps end up pasting the just-restored old clipboard on
    /// top of the user's transcription. 500 ms covers Electron-class apps
    /// under load with comfortable margin and is still imperceptible at
    /// human-reaction-time scale.
    private func finalizeSession() {
        usleep(500_000)
        sessionClipboard?.restore()
        sessionClipboard = nil
        typedSoFar = ""

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pill.hide()
            self.state = .idle
        }
    }

    /// Sync clipboard restoration for error / cancellation paths (model switch
    /// mid-streaming, mic failure, mid-spawn release). Called from main; hops
    /// to the typing queue so we don't trip over an in-flight typeDiff.
    ///
    /// Same race as `finalizeSession`: any clipboard ⌘V we issued during a
    /// just-cancelled streaming session may still be pending in the system
    /// event queue. The sleep ensures it's been consumed before we overwrite
    /// the clipboard with the user's original content.
    private func endSession(restoreClipboard: Bool) {
        streamConsumer?.cancel()
        streamConsumer = nil
        pill.hide()
        if restoreClipboard {
            typingQueue.async { [weak self] in
                usleep(300_000)
                self?.sessionClipboard?.restore()
                self?.sessionClipboard = nil
                self?.typedSoFar = ""
            }
        }
        scheduleReturnToIdle()
    }

    private func scheduleReturnToIdle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.state = .idle
        }
    }
}
