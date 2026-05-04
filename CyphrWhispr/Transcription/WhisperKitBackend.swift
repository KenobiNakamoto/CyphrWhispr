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
/// microphone capture — that conflicts with our `AudioCaptureEngine`. Instead, we run periodic full
/// re-transcriptions of the accumulated buffer (~800 ms cadence) which gives the same UX feel:
/// words appear in the pill shortly after you say them. For typical dictation utterances (<30 s)
/// this is fast enough; for longer dictation we'd switch to chunked streaming in v1.1.
actor WhisperKitBackend: WhisperEngine {
    private var modelName: String
    private let partialIntervalNanos: UInt64
    private var pipe: WhisperKit?
    private var samples: [Float] = []
    private var continuation: AsyncStream<TranscriptUpdate>.Continuation?
    private var partialTask: Task<Void, Never>?

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

        let final = samples
        samples.removeAll(keepingCapacity: true)

        guard !final.isEmpty else {
            continuation?.yield(TranscriptUpdate(text: "", isFinal: true))
            continuation?.finish()
            continuation = nil
            return ""
        }

        let text: String
        do {
            let results = try await pipe.transcribe(audioArray: final)
            text = Self.combine(results: results)
        } catch {
            continuation?.finish()
            continuation = nil
            throw error
        }

        continuation?.yield(TranscriptUpdate(text: text, isFinal: true))
        continuation?.finish()
        continuation = nil
        return text
    }

    private func emitPartial() async {
        guard let pipe else { return }
        guard !samples.isEmpty else { return }
        let snapshot = samples
        do {
            let results = try await pipe.transcribe(audioArray: snapshot)
            let text = Self.combine(results: results)
            continuation?.yield(TranscriptUpdate(text: text, isFinal: false))
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
}
