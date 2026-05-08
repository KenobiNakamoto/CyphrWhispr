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
    /// Set when `pill.onInstallOutroComplete` fires. Sole gate that
    /// promotes the install path from `.spawning` → `.streaming`.
    private var installOutroDone: Bool = false
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

    init(prefs: PreferencesStore = .shared) {
        self.prefs = prefs
        self.whisper = WhisperKitBackend(modelName: prefs.activeModelID)
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

        // Install path: intro complete → kick off the rim-progress driver.
        // Note: installRimTask is a fallback timer — the moment
        // `whisper.warmUp()` actually resolves we cancel the timer, snap
        // the rim to 1.0, and trigger the outro. The timer just gives the
        // user *visible* progress in case the warm-up takes its full
        // 30-90s; without it the rim would sit at 0 looking broken.
        pill.onInstallIntroComplete = { [weak self] in
            self?.startInstallRimSweep()
        }

        // Install path: outro complete → start streaming. We only honour
        // this when we're still in `.spawning` (early hotkey release would
        // have already moved us past .spawning, in which case the outro
        // we triggered before the user gave up should just no-op here).
        pill.onInstallOutroComplete = { [weak self] in
            guard let self else { return }
            guard self.installPathActive else { return }
            self.installOutroDone = true
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
            installOutroDone = false
            installPathActive = false
            spawnBuffer.removeAll(keepingCapacity: false)
            audio.stop()
            endSession(restoreClipboard: true)
        }
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

        // Choose between cinematic spawn (model already warm or warming
        // briefly) and the full install animation (model still loading on
        // a fresh launch). Decision is made once at press time and frozen
        // for this session via `installPathActive` — flipping mid-session
        // would leave the pill choreography in a confused state.
        let useInstallPath = (state == .loadingModel)
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
        // whisperWarmDone gate the cinematic path; installOutroDone gates
        // the install path. We always reset both so cancelled-and-retried
        // sessions start from a clean slate.
        spawnAnimationDone = false
        whisperWarmDone = false
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
                    // Install path: snap the rim to 1.0 (in case the
                    // 30s timer hasn't reached it yet) and play the outro.
                    // Streaming starts when the outro callback fires.
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

    /// Drives the rim from 0 → 1 over `installRimSweepDuration` once the
    /// install intro animation completes. Cancelled and replaced by a snap
    /// to 1.0 the moment `whisper.warmUp()` actually resolves; if the timer
    /// reaches the end before warm-up, the rim sits visually full and we
    /// keep waiting (the outro doesn't fire until warm-up is done).
    ///
    /// 60Hz tick — same cadence WaveformView uses for live audio bars,
    /// chosen because it matches the screen refresh rate on M1+ Macs.
    private func startInstallRimSweep() {
        installRimTask?.cancel()
        installRimTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let start = CACurrentMediaTime()
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - start
                let p = min(1.0, elapsed / Self.installRimSweepDuration)
                self.pill.setInstallProgress(p)
                if p >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60Hz
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
                let finalText = try await self.whisper.finishStream()
                await MainActor.run { self.commitFinalText(finalText) }
            } catch {
                await MainActor.run {
                    self.state = .error("Transcription failed: \(error.localizedDescription)")
                    self.endSession(restoreClipboard: true)
                }
            }
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
