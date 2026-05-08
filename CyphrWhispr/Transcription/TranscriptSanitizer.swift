import Foundation

/// Strips the noise-label artifacts Whisper emits and tidies whitespace, so
/// the user's clipboard / typed output only contains actual speech.
///
/// Three classes of artifact are filtered:
///
///   1. **Special Whisper tokens** in `<|...|>` form — `<|startoftranscript|>`,
///      `<|endoftext|>`, timestamp tokens like `<|0.00|>`, language tags
///      like `<|en|>`, etc. These are tokenizer leftovers and are never
///      legitimate user dictation.
///
///   2. **All-caps bracketed labels** — `[BLANK_AUDIO]`, `[MUSIC]`, `[NOISE]`,
///      `[INAUDIBLE]`, `[NON-ENGLISH SPEECH]`. We match all-caps + underscores
///      + hyphens + spaces inside square brackets so the user remains free
///      to dictate normal mixed-case bracketed text like "see [appendix]"
///      without it being eaten.
///
///   3. **Parenthesised noise labels** — `(speaking in foreign language)`,
///      `(music)`, `(applause)`, `(laughter)`, `(silence)` etc. These are
///      filtered against an explicit allowlist (case-insensitive) so user
///      dictation like "(see page 12)" passes through untouched. If new
///      Whisper artifacts surface, add them to `parentheticalNoiseLabels`.
///
/// All three rules are applied in order, then any double spaces left behind
/// are collapsed and leading/trailing whitespace is trimmed.
enum TranscriptSanitizer {

    // MARK: Patterns

    /// Whisper tokenizer special tokens, e.g. `<|startoftranscript|>`,
    /// `<|0.00|>`, `<|en|>`, `<|endoftext|>`. Anything between `<|` and `|>`.
    private static let specialToken: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"<\|[^|]*\|>"#, options: [])
    }()

    /// All-caps bracketed labels — letters, underscores, hyphens, and spaces
    /// only, all caps. The pattern excludes lowercase so legitimate user
    /// dictation like "see [appendix]" or "[Note]" is left intact.
    private static let bracketArtifact: NSRegularExpression = {
        let pattern = #"\[[A-Z][A-Z_\- ]*\]"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    /// Phrases Whisper emits in parentheses to describe non-speech audio.
    /// Listed explicitly (rather than stripping all parenthesised text)
    /// because users frequently dictate parenthetical asides.
    /// `speaking in <X>` covers every "(speaking in foreign language)",
    /// "(speaking in Spanish)", etc.
    private static let parentheticalNoiseLabels: NSRegularExpression = {
        let labels = [
            #"speaking in [^)]*"#,
            "music",
            "applause",
            "laughter",
            "laughing",
            "crying",
            "coughing",
            "sighing",
            "breathing",
            "no speech",
            "silence",
            "non-english speech",
            "non English speech",
            "foreign language",
            "inaudible",
            "unintelligible",
            "background noise",
            "noise",
            "wind",
        ].joined(separator: "|")
        return try! NSRegularExpression(pattern: #"\((\#(labels))\)"#,
                                        options: [.caseInsensitive])
    }()

    private static let multipleSpaces: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"[ \t]{2,}"#, options: [])
    }()

    // MARK: Public API

    static func clean(_ text: String) -> String {
        var result = text
        result = strip(specialToken, in: result)
        result = strip(bracketArtifact, in: result)
        result = strip(parentheticalNoiseLabels, in: result)
        result = collapse(multipleSpaces, in: result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Helpers

    private static func strip(_ regex: NSRegularExpression, in text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: ""
        )
    }

    private static func collapse(_ regex: NSRegularExpression, in text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: " "
        )
    }
}
