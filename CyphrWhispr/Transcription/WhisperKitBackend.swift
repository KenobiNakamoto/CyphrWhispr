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
        partialIntervalMillis: Int = 800
    ) {
        self.modelName = modelName
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

    func startStream() -> AsyncStream<TranscriptUpdate> {
        partialTask?.cancel()
        partialTask = nil
        samples.removeAll(keepingCapacity: true)
        committedText = ""

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
            let results = try await pipe.transcribe(audioArray: tail)
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
            let results = try await pipe.transcribe(audioArray: snapshot)
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
