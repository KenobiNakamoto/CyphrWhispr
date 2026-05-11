import Foundation
import WhisperKit

enum WhisperBackendError: Error, LocalizedError {
    case notWarmedUp
    case modelLoadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notWarmedUp:
            return "Whisper model has not been loaded yet."
        case .modelLoadFailed(let error):
            return "Failed to load Whisper model: \(error.localizedDescription)"
        }
    }
}

/// Streams partial transcripts as audio is appended, then commits a final transcript on `finishStream`.
///
/// True token-level streaming in WhisperKit requires `AudioStreamTranscriber` which manages its own
/// microphone capture — that conflicts with our `AudioCaptureEngine`. Instead, we run periodic
/// re-transcriptions of a sliding window (~800 ms cadence). After every transcribe, segments that
/// ended sufficiently far in the past are **committed** — their text is locked and their audio is
/// dropped from the buffer, so subsequent partials only re-transcribe the still-uncommitted tail.
/// This bounds three things that would otherwise grow without limit during a long dictation:
///
///  1. **Per-partial transcribe time** — always proportional to the tail window, not the whole session
///  2. **finishStream cost** — finalize is cheap because most of the audio is already committed
///  3. **Live revisions** — Whisper can only revise the still-uncommitted tail, so the user no
///     longer sees mid-session "rewrite the whole transcript" jumps when the model changes its
///     mind about earlier words
actor WhisperKitBackend: WhisperEngine {
    private var modelName: String
    private let partialIntervalNanos: UInt64
    private var pipe: WhisperKit?
    private var samples: [Float] = []
    private var continuation: AsyncStream<TranscriptUpdate>.Continuation?
    private var partialTask: Task<Void, Never>?

    /// Locked text from segments that ended early enough to be considered final.
    /// Their audio has been dropped from `samples`, so partials only ever
    /// re-transcribe the remaining tail. Reset on `startStream` and consumed by
    /// `finishStream`.
    private var committedText: String = ""

    // MARK: - Language preference

    /// User's persisted language preference: a Whisper language code
    /// (`"en"`, `"es"`, …) or the auto sentinel
    /// (`TranscriptionLanguageMode.autoCode`). Updated via `setLanguageCode(_:)`
    /// — effective on the next `startStream()`. Defaults to English so a
    /// brand-new install with the bundled `.en` model behaves identically
    /// to before this feature shipped.
    private var requestedLanguageCode: String = "en"

    /// Once the auto-detect path runs against a stream's first transcribe,
    /// we lock the detected code here for the rest of the session — every
    /// subsequent partial reuses it. Cleared on each `startStream()` so the
    /// next session re-detects from scratch. `nil` means "haven't detected
    /// yet" (or we're not in auto mode — in which case `requestedLanguageCode`
    /// is the source of truth and this stays nil).
    ///
    /// In `autoDetectPerPhrase` mode this gets reset to nil after every
    /// commit boundary, so the next transcribe re-runs LID. That's how
    /// phrase-level code-switching is enabled: "Hola. [pause] Hello."
    /// commits the Spanish segment, clears the lock, re-detects English
    /// on the next transcribe, locks English until the next commit.
    private var sessionLockedLanguage: String?

    /// Audio is captured at 16 kHz mono Float32 by `AudioCaptureEngine`.
    private static let sampleRateHz: TimeInterval = 16_000

    /// Once the buffer holds more than this much audio, segments older than
    /// `commitTailWindowSec` get committed. Below this threshold we keep
    /// everything live (no point committing on a tiny buffer).
    private static let commitMinBufferSec: TimeInterval = 6.0

    /// Trailing window of audio that stays "live" — Whisper can still revise
    /// these segments on subsequent partials. 2 s is enough to absorb the model's
    /// typical revisions (it usually only reconsiders the last word or two as
    /// more context arrives) without making the live-typing feel jumpy.
    private static let commitTailWindowSec: TimeInterval = 2.0

    init(
        modelName: String = "openai_whisper-small.en",
        languageCode: String = "en",
        partialIntervalMillis: Int = 800
    ) {
        self.modelName = modelName
        self.requestedLanguageCode = languageCode
        self.partialIntervalNanos = UInt64(partialIntervalMillis) * 1_000_000
    }

    func warmUp() async throws {
        if pipe != nil { return }
        try await load(modelName: modelName)
    }

    /// Tear down the current pipeline and load a new variant. Used when the
    /// user picks a different model in Settings. We cancel any in-flight stream
    /// first so we don't crash mid-transcription.
    func loadModel(named id: String) async throws {
        // If we're already on this model and it's loaded, no work needed.
        if id == modelName, pipe != nil { return }

        partialTask?.cancel()
        partialTask = nil
        continuation?.finish()
        continuation = nil
        samples.removeAll(keepingCapacity: false)

        // Drop the old pipeline so its Core ML resources are released before we
        // page in the next one. Otherwise we briefly hold both in memory and
        // 8 GB Macs OOM-kill us.
        pipe = nil

        try await load(modelName: id)
        modelName = id
    }

    /// Build a WhisperKit pipeline for the given variant. Pulls models into our
    /// own Application Support folder so we (a) survive Caches eviction and
    /// (b) can show the user what's downloaded.
    ///
    /// `modelFolder` is set only when the variant is already on disk. If we
    /// passed it for a not-yet-downloaded model, WhisperKit's `setupModels`
    /// would skip the download step (it treats a non-nil `modelFolder` as
    /// "user provided a local model, don't download"), then fail when looking
    /// for the absent .mlmodelc files.
    private func load(modelName: String) async throws {
        let isCached = AppSupportPaths.isModelDownloaded(modelName)
        let localFolder: String? = isCached ? AppSupportPaths.modelURL(for: modelName).path : nil

        do {
            let config = WhisperKitConfig(
                model: modelName,
                downloadBase: AppSupportPaths.downloadBase,
                modelFolder: localFolder,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true
            )
            pipe = try await WhisperKit(config)
        } catch {
            throw WhisperBackendError.modelLoadFailed(error)
        }
    }

    /// Update the user's language preference. Effective from the next
    /// `startStream()` call onward — never affects an in-flight stream
    /// (we don't want the language to flip mid-utterance).
    func setLanguageCode(_ code: String) {
        requestedLanguageCode = code
    }

    func startStream() -> AsyncStream<TranscriptUpdate> {
        partialTask?.cancel()
        partialTask = nil
        samples.removeAll(keepingCapacity: true)
        committedText = ""
        // Fresh session = fresh language detection. If the user is in auto
        // mode, we'll re-run language ID against the first non-empty
        // transcribe of THIS session and lock it for the rest.
        sessionLockedLanguage = nil

        let (stream, cont) = AsyncStream<TranscriptUpdate>.makeStream()
        continuation = cont

        let interval = partialIntervalNanos
        partialTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                await self?.emitPartial()
            }
        }
        return stream
    }

    func append(samples newSamples: [Float]) {
        samples.append(contentsOf: newSamples)
    }

    // MARK: - Decode options

    /// Build `DecodingOptions` for the current call. Three cases:
    ///
    ///   1. **Forced language** (`requestedLanguageCode != "auto"`): pin
    ///      `language` to the user's choice. `detectLanguage = false` and
    ///      `usePrefillPrompt = true` so Whisper skips the LID head and
    ///      decodes immediately with the language token prefilled.
    ///
    ///   2. **Auto mode, language already locked for this session**
    ///      (`sessionLockedLanguage != nil`): treated identically to forced
    ///      — we ran detection on the first transcribe and committed to a
    ///      language for the rest of the session, so subsequent transcribes
    ///      use that locked code with the prefill fast-path.
    ///
    ///   3. **Auto mode, no lock yet**: this is the first transcribe of the
    ///      session. Set `detectLanguage = true` and `usePrefillPrompt = false`
    ///      so Whisper runs its LID head on the leading audio. After the
    ///      transcribe returns, we'll inspect `result.language` and lock it
    ///      via `lockSessionLanguage(from:)` so subsequent calls take the
    ///      forced path. The "few hundred ms" detection penalty only hits
    ///      this one transcribe.
    private func currentDecodeOptions() -> DecodingOptions {
        let pinned = effectivePinnedLanguage()
        if let pinned {
            return DecodingOptions(
                task: .transcribe,
                language: pinned,
                usePrefillPrompt: true,
                detectLanguage: false,
                skipSpecialTokens: true
            )
        }
        // First-of-session detection pass.
        return DecodingOptions(
            task: .transcribe,
            language: nil,
            usePrefillPrompt: false,
            detectLanguage: true,
            skipSpecialTokens: true
        )
    }

    /// `nil` if we should run language detection on the next transcribe,
    /// otherwise the language code to pin. Both auto modes resolve to the
    /// session-locked code if we've already detected once for the current
    /// phrase. Per-phrase mode just resets the lock more aggressively
    /// (after each commit, in `emitPartial`).
    private func effectivePinnedLanguage() -> String? {
        if Self.isAutoMode(requestedLanguageCode) {
            return sessionLockedLanguage
        }
        return requestedLanguageCode
    }

    /// After an auto-mode detection transcribe returns, capture the language
    /// it picked so subsequent transcribes in the same session use the
    /// faster prefill path. Idempotent — only sets the lock if we're in
    /// auto mode and haven't locked yet.
    private func lockSessionLanguage(from results: [TranscriptionResult]) {
        guard Self.isAutoMode(requestedLanguageCode),
              sessionLockedLanguage == nil else { return }
        // TranscriptionResult.language is the detected code (when LID ran)
        // or the requested language (when prefilled). Take the first
        // non-empty value across the result set.
        if let detected = results.first(where: { !$0.language.isEmpty })?.language {
            sessionLockedLanguage = detected
        }
    }

    /// True for both auto-detect variants — locked-per-session and
    /// per-phrase. Centralised so we never miss one of the two sentinels
    /// when reasoning about whether to invoke language detection.
    private static func isAutoMode(_ code: String) -> Bool {
        code == TranscriptionLanguageMode.autoCode
            || code == TranscriptionLanguageMode.autoPerPhraseCode
    }

    func finishStream() async throws -> String {
        partialTask?.cancel()
        partialTask = nil

        guard let pipe else { throw WhisperBackendError.notWarmedUp }

        let tail = samples
        samples.removeAll(keepingCapacity: true)
        let priorCommitted = committedText
        committedText = ""

        // Empty tail: whatever was committed during streaming IS the full text.
        guard !tail.isEmpty else {
            // CRITICAL: do NOT yield the final via `continuation`. The
            // streamConsumer in AppCoordinator iterates this AsyncStream and
            // would race commitFinalText on `typingQueue` — its typeDiff path
            // uses pasteWithoutRestore (clipboard ⌘V) which races the
            // clipboard restore in finalizeSession. commitFinalText receives
            // the return value here and routes it through `typeUnicode`
            // instead. Just close the stream so the consumer's for-await exits.
            continuation?.finish()
            continuation = nil
            return priorCommitted
        }

        let tailText: String
        do {
            let options = currentDecodeOptions()
            let results = try await pipe.transcribe(audioArray: tail,
                                                    decodeOptions: options)
            // If this was an auto-mode session and we never had time to
            // detect during streaming (very short utterance), the final
            // transcribe IS the detection. Lock from the result so any
            // future session inherits a sensible default? No — we
            // intentionally clear `sessionLockedLanguage` on the next
            // `startStream()`, so the locking here only matters if the
            // result text is the only thing we'd emit. Locking is
            // harmless either way.
            lockSessionLanguage(from: results)
            tailText = Self.combine(results: results)
        } catch {
            continuation?.finish()
            continuation = nil
            throw error
        }

        continuation?.finish()
        continuation = nil
        return Self.joinSpaceAware(priorCommitted, tailText)
    }

    private func emitPartial() async {
        guard let pipe else { return }
        guard !samples.isEmpty else { return }
        let snapshot = samples
        do {
            let options = currentDecodeOptions()
            let results = try await pipe.transcribe(audioArray: snapshot,
                                                    decodeOptions: options)
            // If we just ran auto-detection, lock the result so subsequent
            // partials use the faster prefilled path. No-op when not in
            // auto mode or when already locked.
            lockSessionLanguage(from: results)
            let allSegments = results.flatMap { $0.segments }

            // Decide which segments are committable — old enough that Whisper
            // shouldn't be reconsidering them. We only commit when the buffer
            // is meaningfully long (avoids over-committing tiny early
            // utterances) and only segments that fully ended before the
            // trailing live window.
            let bufferDurationSec = TimeInterval(snapshot.count) / Self.sampleRateHz
            var newCommittedSegs: [TranscriptionSegment] = []
            var stillLiveSegs: [TranscriptionSegment] = []
            if bufferDurationSec >= Self.commitMinBufferSec {
                let cutoff = bufferDurationSec - Self.commitTailWindowSec
                var crossedTail = false
                for seg in allSegments {
                    if !crossedTail && Double(seg.end) < cutoff {
                        newCommittedSegs.append(seg)
                    } else {
                        crossedTail = true
                        stillLiveSegs.append(seg)
                    }
                }
            } else {
                stillLiveSegs = allSegments
            }

            // Commit: append the newly-committed segment text and drop the
            // matching audio from the front of `samples`. Note that `samples`
            // may have grown during the awaited transcribe (audio capture is
            // still appending) — we drop based on the snapshot's commit point,
            // which is still a valid prefix of the current array because we
            // only ever append at the tail.
            if let lastCommitted = newCommittedSegs.last {
                let committedSampleCount = Int(Double(lastCommitted.end) * Self.sampleRateHz)
                if committedSampleCount > 0 && committedSampleCount <= samples.count {
                    samples.removeFirst(committedSampleCount)
                }
                let newText = Self.combineSegments(newCommittedSegs)
                if !newText.isEmpty {
                    committedText = Self.joinSpaceAware(committedText, newText)
                }
                // Per-phrase mode: every successful commit ends a "phrase"
                // from the user's POV (the audio for that phrase is dropped
                // from the live buffer). Reset the language lock so the
                // next transcribe re-runs LID and can pick a different
                // language for the next phrase. This is what enables
                // "Hola [pause] Hello [pause] Hallo" to be transcribed
                // each phrase in its own language. The cost: every commit
                // pays the LID penalty on the next transcribe.
                if requestedLanguageCode == TranscriptionLanguageMode.autoPerPhraseCode {
                    sessionLockedLanguage = nil
                }
            }

            let liveText = Self.combineSegments(stillLiveSegs)
            let displayed = Self.joinSpaceAware(committedText, liveText)
            continuation?.yield(TranscriptUpdate(text: displayed, isFinal: false))
        } catch {
            // Best-effort; will retry on next tick or be superseded by the final pass.
        }
    }

    private static func combine(results: [TranscriptionResult]) -> String {
        results
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Join Whisper segment texts into a single normalised string. Each
    /// segment's text is trimmed independently before joining so we don't
    /// pile up double-spaces from segments that have leading/trailing
    /// whitespace.
    private static func combineSegments(_ segs: [TranscriptionSegment]) -> String {
        segs
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Concatenate two text fragments with exactly one space between them.
    /// Used to glue committedText onto live partials and to glue committed
    /// onto the final tail in `finishStream` — handles all the empty-string
    /// edge cases without producing leading or trailing whitespace.
    private static func joinSpaceAware(_ lhs: String, _ rhs: String) -> String {
        if lhs.isEmpty { return rhs }
        if rhs.isEmpty { return lhs }
        return lhs + " " + rhs
    }
}
