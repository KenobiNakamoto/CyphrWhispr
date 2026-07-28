import Foundation

/// A completed transcription of a file with per-segment timestamps.
///
/// Produced by `FileTranscriber`, consumed by `TranscriptExporter` and the
/// result-window view. Immutable by design — once a transcription has run,
/// the result is a frozen value that travels into the UI without further
/// coordination with the engine. Carrying the segments (not just the text)
/// is what lets us emit SRT/VTT exports on top of the plain text.
/// `Codable` so a completed transcript can be archived to disk (see
/// `TranscriptArchive`) and reloaded instantly on "Reopen" instead of being
/// re-derived by running the source audio back through Whisper. The compiler
/// synthesises `Codable` over the stored properties; the derived `plainText` /
/// `sourceFilename` round-trip as stored values (they stay consistent because
/// we only ever encode what the designated init already computed).
struct FileTranscript: Sendable, Equatable, Codable {
    /// User-readable filename (no path). Used as the result-window title and
    /// the default basename when the user picks Save as…
    let sourceFilename: String

    /// Original URL the audio came from. Kept around so Save as… can default
    /// to the same parent folder and the same basename.
    let sourceURL: URL

    /// Total duration of the source audio in seconds. Derived from the
    /// decoded sample count, not from `AVAsset.duration`, so it matches what
    /// Whisper actually saw (any trailing silence the decoder skipped is not
    /// counted).
    let durationSeconds: TimeInterval

    /// Time-ordered segments. WhisperKit returns these from the model itself;
    /// they're the basis of every subtitle export and the natural unit for
    /// later features like click-to-jump playback or per-segment highlight.
    let segments: [Segment]

    /// Pre-joined plain text. Computed once at construction so the result-
    /// window text view doesn't recompute on every redraw.
    let plainText: String

    struct Segment: Sendable, Equatable, Codable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    init(sourceURL: URL, durationSeconds: TimeInterval, segments: [Segment]) {
        self.sourceURL = sourceURL
        self.sourceFilename = sourceURL.lastPathComponent
        self.durationSeconds = durationSeconds
        self.segments = segments
        // Trim each segment before joining so we don't pile up double-spaces
        // from segments that come back with leading/trailing whitespace —
        // same recipe `WhisperKitBackend.combineSegments` uses on the live
        // path.
        self.plainText = segments
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
