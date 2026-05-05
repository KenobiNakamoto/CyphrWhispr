import Foundation
import AppKit
import Combine

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
            whisperWarmAwaiter?.cancel()
            whisperWarmAwaiter = nil
            spawnAnimationDone = false
            whisperWarmDone = false
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

        // Enter spawning state — pill plays the cinematic appearance, audio
        // capture starts immediately, samples buffer locally instead of
        // streaming until both the animation completes and whisper is warm.
        state = .spawning
        spawnBuffer.removeAll(keepingCapacity: true)
        pill.show()

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

        // Reset both readiness flags. The pill controller's `onSpawnComplete`
        // callback (wired up in `start()`) flips `spawnAnimationDone`; the
        // warm-up Task below flips `whisperWarmDone`. The second one to fire
        // calls `maybeBeginStreaming()` which actually advances state.
        spawnAnimationDone = false
        whisperWarmDone = false

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
                self.maybeBeginStreaming()
            }
        }
    }

    /// Called from two places — both fire only after the precondition they
    /// represent has been met:
    ///   • `pill.onSpawnComplete` callback flips `spawnAnimationDone`
    ///   • the warm-up Task above flips `whisperWarmDone`
    /// Whichever arrives second satisfies the guard and advances state to
    /// `.streaming`. Idempotent — re-entering after `.streaming` is a no-op.
    private func maybeBeginStreaming() {
        guard state == .spawning else { return }
        guard spawnAnimationDone && whisperWarmDone else { return }
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
        // the pill, restore clipboard.
        if state == .spawning {
            whisperWarmAwaiter?.cancel()
            whisperWarmAwaiter = nil
            spawnAnimationDone = false
            whisperWarmDone = false
            spawnBuffer.removeAll(keepingCapacity: false)
            audio.stop()
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
    /// the smallest possible backspace+paste sequence. Must be called on
    /// `typingQueue`.
    private func typeDiff(target: String) {
        guard target != typedSoFar else { return }

        let commonPrefix = typedSoFar.commonPrefix(with: target)
        let backspaceCount = typedSoFar.count - commonPrefix.count
        let suffix = String(target.dropFirst(commonPrefix.count))

        do {
            if backspaceCount > 0 {
                try injector.sendBackspaces(backspaceCount)
            }
            if !suffix.isEmpty {
                try injector.pasteWithoutRestore(suffix)
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
            self.typeDiff(target: cleaned)
            self.finalizeSession()
        }

        state = .injecting
    }

    /// Restore the user's original clipboard, drop the typing-state, and bounce
    /// back to idle. Called from `typingQueue`.
    ///
    /// The sleep before restore is critical: the final ⌘V CGEvent has been
    /// posted to the system event queue but the receiving app hasn't necessarily
    /// consumed it yet. If we restore the clipboard too soon, the app's paste
    /// reads the (just-restored) old content and pastes that on top of the
    /// transcription. 200 ms is conservative — still imperceptible to the user
    /// but enough for even sluggish Electron apps to read the pasteboard.
    private func finalizeSession() {
        usleep(200_000)
        sessionClipboard?.restore()
        sessionClipboard = nil
        typedSoFar = ""

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pill.hide()
            self.state = .idle
        }
    }

    /// Sync clipboard restoration for error paths. Called from main; hops to
    /// the typing queue so we don't trip over an in-flight typeDiff.
    private func endSession(restoreClipboard: Bool) {
        streamConsumer?.cancel()
        streamConsumer = nil
        pill.hide()
        if restoreClipboard {
            typingQueue.async { [weak self] in
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
