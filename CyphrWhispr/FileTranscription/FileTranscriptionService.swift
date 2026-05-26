import Foundation
import Combine

/// One-job orchestrator that drives a single file through the
/// decode → transcribe pipeline.
///
/// One instance per result window — multiple drops produce multiple services
/// running concurrently. Decode is parallel-safe (AVFoundation streams off
/// the global executor). The WhisperKit `transcribe(audioArray:)` calls
/// serialise naturally because each service holds its own `FileTranscriber`
/// actor, and Core ML's GPU-context access is single-instance per Mac.
///
/// `status` is monotonic — once `.done(transcript)` or `.failed(message)` is
/// set the service is terminal and never transitions again. The view
/// observes it via `@Published`, so the result window UI re-renders against
/// the latest state on each tick.
@MainActor
final class FileTranscriptionService: ObservableObject {
    enum Status: Equatable {
        case idle
        /// `progress` in 0...1, derived from how many seconds of audio have
        /// been pulled out of the file vs the file's total duration.
        case decoding(progress: Double)
        /// WhisperKit's `transcribe(audioArray:)` doesn't surface mid-call
        /// progress through its public API, so this state is effectively
        /// indeterminate — the view renders an indeterminate spinner.
        case transcribing
        case done(FileTranscript)
        case failed(message: String)

        /// True while the pipeline is still doing work — used by the view to
        /// gate the "Cancel" button vs the "Copy / Save" buttons.
        var isInFlight: Bool {
            switch self {
            case .decoding, .transcribing: return true
            default: return false
            }
        }
    }

    @Published private(set) var status: Status = .idle

    let sourceURL: URL
    let modelName: String
    let languageCode: String

    private let transcriber: FileTranscriber
    private var workTask: Task<Void, Never>?

    init(sourceURL: URL,
         modelName: String,
         languageCode: String) {
        self.sourceURL = sourceURL
        self.modelName = modelName
        self.languageCode = languageCode
        self.transcriber = FileTranscriber(modelName: modelName)
    }

    /// Kick off decode + transcribe. Safe to call exactly once per service —
    /// subsequent calls no-op so a double-tap on the auto-start (or a redraw
    /// race in the view) doesn't fire the pipeline twice.
    func start() {
        guard case .idle = status else { return }
        status = .decoding(progress: 0)

        workTask = Task { [weak self] in
            await self?.runPipeline()
        }
    }

    /// Best-effort cancellation. Sets `.failed(message: "Cancelled.")` so the
    /// UI can drop the spinner and the user can close the window. The
    /// decoder cooperates via `Task.isCancelled`; WhisperKit's
    /// `transcribe(audioArray:)` doesn't expose cancellation, so a cancel
    /// during the transcribe phase still lets that call complete in the
    /// background before being discarded.
    func cancel() {
        workTask?.cancel()
        workTask = nil
        status = .failed(message: "Cancelled.")
    }

    // MARK: - Pipeline

    private func runPipeline() async {
        // Step 1 — decode the file into a 16 kHz mono Float32 buffer.
        let samples: [Float]
        let durationSeconds: TimeInterval
        do {
            samples = try await AssetAudioDecoder.decode(url: sourceURL) { [weak self] p in
                // The progress callback fires from the global executor (the
                // decode runs off-main so it doesn't stall the UI). Hop back
                // to the main actor before touching @Published state.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .decoding = self.status {
                        self.status = .decoding(progress: p)
                    }
                }
            }
            // Derive duration from the actual sample count rather than
            // `AVAsset.duration` — matches what Whisper saw.
            durationSeconds = TimeInterval(samples.count) / 16_000.0
        } catch is CancellationError {
            self.status = .failed(message: "Cancelled.")
            return
        } catch {
            self.status = .failed(message: error.localizedDescription)
            return
        }

        guard !Task.isCancelled else {
            status = .failed(message: "Cancelled.")
            return
        }

        // Guard against silent / empty files. WhisperKit will happily accept
        // a zero-length buffer and return an empty transcript, but the UX is
        // confusing — "done" with nothing in it. Surface as a failure so the
        // window reads obviously.
        guard !samples.isEmpty else {
            status = .failed(message: "No audio decoded from this file.")
            return
        }

        // Step 2 — load the model (no-op if already loaded for this service)
        // and run a one-shot transcribe.
        status = .transcribing
        do {
            try await transcriber.load(modelName: modelName)
        } catch {
            status = .failed(message: error.localizedDescription)
            return
        }

        let transcript: FileTranscript
        do {
            transcript = try await transcriber.transcribe(
                samples: samples,
                sourceURL: sourceURL,
                durationSeconds: durationSeconds,
                languageCode: languageCode
            )
        } catch {
            status = .failed(message: error.localizedDescription)
            return
        }

        status = .done(transcript)
    }
}
