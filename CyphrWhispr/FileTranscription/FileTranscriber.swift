import Foundation
import WhisperKit

enum FileTranscriberError: Error, LocalizedError {
    case notLoaded
    case modelLoadFailed(Error)
    case transcribeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "Whisper model hasn't been loaded for file transcription."
        case .modelLoadFailed(let e):
            return "Failed to load Whisper model: \(e.localizedDescription)"
        case .transcribeFailed(let e):
            return "Transcription failed: \(e.localizedDescription)"
        }
    }
}

/// One-shot WhisperKit transcription against a pre-decoded sample buffer.
///
/// Deliberately separate from `WhisperKitBackend` (the live-dictation engine).
/// That one runs a periodic sliding-window partial loop, holds per-session
/// `committedText` and `sessionLockedLanguage` state, and is reentrancy-
/// sensitive because its `partialTask` interleaves on the same actor as
/// `append(samples:)`. File transcription has a wholly different shape: one
/// `pipe.transcribe(audioArray:)` call against the full Float32 array, no
/// partials, no commit/tail bookkeeping. Sharing the engine instance would
/// scramble the live path's state and vice versa, so we hold our own
/// `WhisperKit` here.
///
/// Cost: one extra WhisperKit instance loaded when a file is being processed.
/// Both pull from the same `AppSupportPaths` model cache, so the on-disk
/// footprint doesn't double — only the RAM-resident pipeline.
actor FileTranscriber {
    private var modelName: String
    private var pipe: WhisperKit?

    init(modelName: String) {
        self.modelName = modelName
    }

    /// Materialise the WhisperKit pipeline for the configured model.
    /// Idempotent when the same model is already loaded; swaps the pipe (and
    /// releases the previous one first so 8 GB Macs don't briefly hold two
    /// large Core ML graphs simultaneously) when the model changes.
    func load(modelName id: String) async throws {
        if id == modelName, pipe != nil { return }

        pipe = nil

        let isCached = AppSupportPaths.isModelDownloaded(id)
        let localFolder: String? = isCached ? AppSupportPaths.modelURL(for: id).path : nil
        do {
            let config = WhisperKitConfig(
                model: id,
                downloadBase: AppSupportPaths.downloadBase,
                modelFolder: localFolder,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true
            )
            pipe = try await WhisperKit(config)
            modelName = id
        } catch {
            throw FileTranscriberError.modelLoadFailed(error)
        }
    }

    /// Transcribe a pre-decoded 16 kHz mono Float32 buffer. Returns a
    /// `FileTranscript` carrying both the plain text and per-segment
    /// timestamps — `TranscriptExporter` uses the segments to emit
    /// SRT/VTT output.
    ///
    /// The file path skips the live engine's language-locking dance.
    /// Whatever code the caller specified is honoured directly: an `auto`
    /// sentinel asks Whisper to detect, anything else pins the language
    /// with the prefill fast-path.
    func transcribe(samples: [Float],
                    sourceURL: URL,
                    durationSeconds: TimeInterval,
                    languageCode: String) async throws -> FileTranscript {
        guard let pipe else { throw FileTranscriberError.notLoaded }

        let isAuto = (languageCode == TranscriptionLanguageMode.autoCode
                      || languageCode == TranscriptionLanguageMode.autoPerPhraseCode)
        let options = DecodingOptions(
            task: .transcribe,
            language: isAuto ? nil : languageCode,
            usePrefillPrompt: !isAuto,
            detectLanguage: isAuto,
            skipSpecialTokens: true,
            withoutTimestamps: false
        )

        let results: [TranscriptionResult]
        do {
            results = try await pipe.transcribe(audioArray: samples,
                                                decodeOptions: options)
        } catch {
            throw FileTranscriberError.transcribeFailed(error)
        }

        // Flatten WhisperKit's `[TranscriptionResult]` (one entry per 30 s
        // chunk it processed internally) into a single ordered segment list
        // for the FileTranscript.
        let segments = results
            .flatMap { $0.segments }
            .map { seg in
                FileTranscript.Segment(start: TimeInterval(seg.start),
                                       end: TimeInterval(seg.end),
                                       text: seg.text)
            }

        return FileTranscript(sourceURL: sourceURL,
                              durationSeconds: durationSeconds,
                              segments: segments)
    }
}
