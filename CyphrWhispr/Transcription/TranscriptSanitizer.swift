import Foundation

/// Strips the special tokens Whisper emits when there's no speech in a window
/// (e.g. `[BLANK_AUDIO]`, `[MUSIC]`, `[NOISE]`, `[INAUDIBLE]`, `[SILENCE]`)
/// and tidies whitespace.
///
/// We only filter all-caps bracketed tokens — leaving the user free to dictate
/// regular bracketed text like "see [appendix]" untouched.
enum TranscriptSanitizer {
    private static let bracketArtifact: NSRegularExpression = {
        // Whisper artifacts are always ALL CAPS (with optional underscores or
        // spaces) inside square brackets. Match that and only that.
        let pattern = #"\[[A-Z][A-Z_ ]*\]"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let multipleSpaces: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"[ \t]{2,}"#, options: [])
    }()

    static func clean(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)

        var result = bracketArtifact.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: ""
        )

        let collapsedRange = NSRange(result.startIndex..., in: result)
        result = multipleSpaces.stringByReplacingMatches(
            in: result,
            options: [],
            range: collapsedRange,
            withTemplate: " "
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
