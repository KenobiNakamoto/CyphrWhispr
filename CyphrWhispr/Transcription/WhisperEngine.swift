import Foundation

/// A partial or final transcript chunk emitted by the streaming engine.
struct TranscriptUpdate {
    /// The full text known so far. Streaming engines may revise earlier tokens
    /// as more context arrives, so consumers should always replace with `text`,
    /// not append.
    let text: String
    /// True only on the last update emitted for a given session.
    let isFinal: Bool
}

protocol WhisperEngine: AnyObject, Sendable {
    /// Fully load the active model. Idempotent. May take 30-90s on first call
    /// (Core ML model compilation) — show progress to the user.
    func warmUp() async throws

    /// Replace the active model with the given variant ID (matches `WhisperModel.id`).
    /// Triggers a download if the model isn't cached yet, then a fresh compile.
    /// Cancels any in-flight stream first.
    func loadModel(named id: String) async throws

    /// Set the user's language preference for subsequent sessions. Pass an
    /// ISO-639-style Whisper language code (`"en"`, `"es"`, `"ja"`, …) to
    /// pin to a specific language, or `TranscriptionLanguageMode.autoCode`
    /// (`"auto"`) to auto-detect on the first audio chunk and lock for the
    /// rest of the session. Effective on the next `startStream()` call;
    /// has no effect on an in-flight session (we don't want the language
    /// to flip mid-utterance — that's exactly the flapping behaviour
    /// every other live-dictation tool avoids).
    ///
    /// Calling with the auto sentinel on an English-only model variant is
    /// a no-op at the engine level — `.en` models can only decode English
    /// regardless of this setting. The Settings UI is responsible for
    /// hiding the picker in that case.
    func setLanguageCode(_ code: String) async

    /// Begin a streaming transcription session. The returned stream emits
    /// partials as they arrive and a final update on completion.
    func startStream() async -> AsyncStream<TranscriptUpdate>

    /// Append PCM audio (16kHz mono Float32) to the active session.
    func append(samples: [Float]) async

    /// Mark the session complete and produce the final transcription.
    func finishStream() async throws -> String
}
