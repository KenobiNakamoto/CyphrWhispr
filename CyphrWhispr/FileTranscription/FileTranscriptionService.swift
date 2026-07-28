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
        /// `progress` in 0...1, derived from WhisperKit's segment-discovery
        /// callback (furthest transcribed timestamp / total duration). Starts at
        /// 0 — which also covers the brief model-load step before the first
        /// segment lands — and climbs as windows are processed.
        case transcribing(progress: Double)
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

    /// The language the most recent transcribe pass ran with. Published so the
    /// result window's language picker can reflect the active choice (and tick
    /// the matching row) without holding its own copy. Mutated only through
    /// `retranscribe(languageCode:)`.
    @Published private(set) var languageCode: String

    let sourceURL: URL
    let modelName: String

    /// Invoked on the main actor whenever a *genuine* transcribe pass produces
    /// a transcript — the initial run and every language re-transcribe, but NOT
    /// a preloaded reopen (which seeds `.done` in its initializer without
    /// running anything). The result-window controller sets this to archive the
    /// transcript into recents and mirror it into the History vault. Living on a
    /// callback rather than the `.done` status keeps reopen-from-archive from
    /// re-recording a transcript that's already saved.
    var onTranscribed: ((FileTranscript) -> Void)?

    private let transcriber: FileTranscriber
    private var workTask: Task<Void, Never>?

    /// The decoded 16 kHz mono Float32 buffer, retained after the first decode
    /// so `retranscribe(languageCode:)` can re-run Whisper against a different
    /// language without paying the decode cost a second time. `nil` until the
    /// initial decode completes — and stays `nil` for a preloaded reopen, whose
    /// audio was never decoded in this session (a language override there falls
    /// back to decoding the source file).
    private var decodedSamples: [Float]?
    private var decodedDurationSeconds: TimeInterval = 0

    init(sourceURL: URL,
         modelName: String,
         languageCode: String) {
        self.sourceURL = sourceURL
        self.modelName = modelName
        self.languageCode = languageCode
        self.transcriber = FileTranscriber(modelName: modelName)
    }

    /// Construct a service that's already finished — seeded with a transcript
    /// loaded from the archive. Used by "Reopen" so the result window shows the
    /// saved transcript immediately without decoding or transcribing. `start()`
    /// no-ops because the status isn't `.idle`. A language override still works:
    /// `retranscribe(...)` finds no cached samples and decodes the source file.
    init(preloaded transcript: FileTranscript,
         modelName: String,
         languageCode: String) {
        self.sourceURL = transcript.sourceURL
        self.modelName = modelName
        self.languageCode = languageCode
        self.transcriber = FileTranscriber(modelName: modelName)
        self.status = .done(transcript)
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

    /// Re-run transcription in a different language, reusing the audio we
    /// already decoded. The result window's language picker calls this when the
    /// user overrides the auto-detected (or seeded) language — e.g. auto-detect
    /// guessed wrong, or they want to force a specific language.
    ///
    /// No-op when the language is unchanged, or before the first decode has
    /// finished (no cached samples yet — the picker is only shown in the `.done`
    /// state, so in practice samples always exist when this is reachable, but we
    /// guard anyway). Cancels any in-flight work first so two passes can't race
    /// onto the terminal `status`.
    func retranscribe(languageCode newCode: String) {
        guard newCode != languageCode else { return }
        languageCode = newCode
        workTask?.cancel()

        if decodedSamples != nil {
            // Audio already in memory (initial run earlier this session) —
            // re-run just the transcribe step at the new language.
            status = .transcribing(progress: 0)
            workTask = Task { [weak self] in
                await self?.runTranscribe()
            }
        } else {
            // Reopened from the archive: we have the transcript but not the
            // samples. Decode the source file from scratch, then transcribe.
            // This is the one path that re-reads the audio, and only because a
            // language change genuinely requires re-running the model.
            status = .decoding(progress: 0)
            workTask = Task { [weak self] in
                await self?.runPipeline()
            }
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

        // Cache the decoded audio so a later language override
        // (`retranscribe(languageCode:)`) can re-run Whisper without paying the
        // decode cost again.
        decodedSamples = samples
        decodedDurationSeconds = durationSeconds

        // Step 2 — load the model and run a one-shot transcribe.
        status = .transcribing(progress: 0)
        await runTranscribe()
    }

    /// Load the model (no-op if already loaded for this service) and run a
    /// one-shot transcribe of the cached samples at the current `languageCode`.
    /// Shared by the initial pipeline and every `retranscribe(...)` override.
    /// Assumes `status` is already `.transcribing` and `decodedSamples` is set.
    private func runTranscribe() async {
        guard let samples = decodedSamples else {
            status = .failed(message: "No decoded audio to transcribe.")
            return
        }

        do {
            try await transcriber.load(modelName: modelName)
        } catch {
            status = .failed(message: error.localizedDescription)
            return
        }

        guard !Task.isCancelled else { return }

        let transcript: FileTranscript
        do {
            transcript = try await transcriber.transcribe(
                samples: samples,
                sourceURL: sourceURL,
                durationSeconds: decodedDurationSeconds,
                languageCode: languageCode,
                progressHandler: { [weak self] fraction in
                    // Fires from a WhisperKit worker thread — hop to the main
                    // actor to touch @Published state. Only advance while we're
                    // still in the transcribing state, so a late callback can't
                    // resurrect progress after cancellation or completion.
                    Task { @MainActor [weak self] in
                        guard let self, case .transcribing = self.status else { return }
                        self.status = .transcribing(progress: fraction)
                    }
                }
            )
        } catch {
            status = .failed(message: error.localizedDescription)
            return
        }

        // A retranscribe override that was superseded (user picked again before
        // this finished) cancels the task — don't clobber the newer pass.
        guard !Task.isCancelled else { return }
        // Notify before flipping status so the archive write lands ahead of any
        // observer reacting to `.done` (e.g. a future auto-reveal).
        onTranscribed?(transcript)
        status = .done(transcript)
    }
}
