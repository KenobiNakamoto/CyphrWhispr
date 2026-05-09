import Foundation

/// User-facing language preference for transcription. Resolved at session
/// start into the actual code WhisperKit accepts.
///
/// Three modes, mirroring what every other live-dictation tool ships:
///   • `englishOnly` — pin to English. The default for `.en` model variants
///     and the only valid option when an English-only model is loaded.
///   • `forced(code:)` — pin to a specific language. The user knows which
///     language they'll dictate in this session and wants the highest-
///     accuracy path (no language-detection penalty, no flapping).
///   • `autoDetect` — let Whisper's language-ID head pick from the first
///     ~1.5 s of audio, then **lock** for the rest of the session. This
///     is the friendly default for multilingual users; no other tool
///     re-detects per utterance because Whisper-class models flap when
///     they do.
///
/// The serialised form (what we put in UserDefaults) is a single string:
///   • `"auto"` for autoDetect
///   • `"en"`, `"es"`, … for forced(code:)
/// Stored as `String` (not enum raw value) so the UserDefaults schema is
/// human-debuggable and trivial to migrate.
enum TranscriptionLanguageMode: Equatable, Hashable, Sendable {
    case englishOnly
    case forced(code: String)
    case autoDetect

    /// Persisted form for UserDefaults. `englishOnly` and `forced("en")`
    /// both serialise to `"en"` so we round-trip via `forced(code:)`.
    var persistedCode: String {
        switch self {
        case .englishOnly:        return "en"
        case .forced(let code):   return code
        case .autoDetect:         return Self.autoCode
        }
    }

    /// Decode from the persisted string. `"auto"` → autoDetect,
    /// anything else → forced(code:). englishOnly is reserved for the
    /// view-model layer to use when an `.en`-only model is loaded — at
    /// the persistence layer we only see `"en"` for English.
    static func from(persistedCode raw: String?) -> TranscriptionLanguageMode {
        guard let raw, !raw.isEmpty else { return .autoDetect }
        if raw == autoCode { return .autoDetect }
        return .forced(code: raw)
    }

    /// Sentinel string for the auto-detect mode. Avoid bare `"auto"`
    /// scattered through the codebase.
    static let autoCode = "auto"
}

/// One pickable language entry. The `code` is a Whisper language code
/// (ISO 639-1 lowercase for most; some Whisper-specific overrides like
/// `yue` for Cantonese).
struct TranscriptionLanguage: Identifiable, Hashable, Sendable {
    let code: String
    /// English name for the picker label.
    let displayName: String
    /// Native-script name for the picker subtitle (e.g. "Español", "中文").
    /// `nil` for English / Auto since the displayName already reads natively.
    let nativeName: String?

    var id: String { code }
}

/// Curated set of languages for the picker. Whisper supports ~99 languages;
/// we ship the top ~30 by global speaker count + every language Apple
/// `SpeechTranscriber` supports (so the picker contents don't change when
/// we add the macOS 26 engine).
///
/// Codes match Whisper's tokenizer language tokens. Cross-checked against
/// `openai/whisper`'s `tokenizer.py` LANGUAGES dict.
enum TranscriptionLanguageCatalog {
    /// The "let Whisper figure it out" entry, always sorted to the top of
    /// any picker.
    static let auto = TranscriptionLanguage(
        code: TranscriptionLanguageMode.autoCode,
        displayName: "Auto-detect",
        nativeName: nil
    )

    /// All curated languages, English first (it's the most common pick),
    /// then alphabetical by display name. Native names use the language's
    /// own script so the picker reads the way speakers expect.
    ///
    /// Coverage philosophy: every major European language (including the
    /// Balkans + the Baltics + Iberian regional languages) plus the most-
    /// spoken Asian languages plus a handful of African / global picks.
    /// Whisper itself supports ~99 languages; the long tail (Hawaiian,
    /// Tibetan, Yoruba, Hausa, etc.) lives in `WhisperOfficialLanguages`
    /// and we expose it on demand via the "More…" picker affordance once
    /// someone asks. Until then, 59 entries is enough to feel exhaustive
    /// without being unmanageable in a pull-down menu.
    ///
    /// Every code in this list MUST also appear in
    /// `WhisperOfficialLanguages.codes` — there's a unit test enforcing it.
    static let supported: [TranscriptionLanguage] = [
        // English first — most common pick, deliberately not alphabetical.
        .init(code: "en", displayName: "English",     nativeName: nil),

        // Then alphabetical by English display name. Native names use the
        // language's own script. Where the native name == the English
        // display name (Afrikaans, Tagalog), nativeName is nil to avoid
        // rendering "X — X" in the picker subtitle.
        .init(code: "af", displayName: "Afrikaans",   nativeName: nil),
        .init(code: "sq", displayName: "Albanian",    nativeName: "Shqip"),
        .init(code: "ar", displayName: "Arabic",      nativeName: "العربية"),
        .init(code: "eu", displayName: "Basque",      nativeName: "Euskara"),
        .init(code: "be", displayName: "Belarusian",  nativeName: "Беларуская"),
        .init(code: "bn", displayName: "Bengali",     nativeName: "বাংলা"),
        .init(code: "bs", displayName: "Bosnian",     nativeName: "Bosanski"),
        .init(code: "bg", displayName: "Bulgarian",   nativeName: "Български"),
        .init(code: "yue", displayName: "Cantonese",  nativeName: "粵語"),
        .init(code: "ca", displayName: "Catalan",     nativeName: "Català"),
        .init(code: "zh", displayName: "Chinese",     nativeName: "中文"),
        .init(code: "hr", displayName: "Croatian",    nativeName: "Hrvatski"),
        .init(code: "cs", displayName: "Czech",       nativeName: "Čeština"),
        .init(code: "da", displayName: "Danish",      nativeName: "Dansk"),
        .init(code: "nl", displayName: "Dutch",       nativeName: "Nederlands"),
        .init(code: "et", displayName: "Estonian",    nativeName: "Eesti"),
        .init(code: "fi", displayName: "Finnish",     nativeName: "Suomi"),
        .init(code: "fr", displayName: "French",      nativeName: "Français"),
        .init(code: "gl", displayName: "Galician",    nativeName: "Galego"),
        .init(code: "de", displayName: "German",      nativeName: "Deutsch"),
        .init(code: "el", displayName: "Greek",       nativeName: "Ελληνικά"),
        .init(code: "he", displayName: "Hebrew",      nativeName: "עברית"),
        .init(code: "hi", displayName: "Hindi",       nativeName: "हिन्दी"),
        .init(code: "hu", displayName: "Hungarian",   nativeName: "Magyar"),
        .init(code: "is", displayName: "Icelandic",   nativeName: "Íslenska"),
        .init(code: "id", displayName: "Indonesian",  nativeName: "Bahasa Indonesia"),
        .init(code: "it", displayName: "Italian",     nativeName: "Italiano"),
        .init(code: "ja", displayName: "Japanese",    nativeName: "日本語"),
        .init(code: "ko", displayName: "Korean",      nativeName: "한국어"),
        .init(code: "lv", displayName: "Latvian",     nativeName: "Latviešu"),
        .init(code: "lt", displayName: "Lithuanian",  nativeName: "Lietuvių"),
        .init(code: "mk", displayName: "Macedonian",  nativeName: "Македонски"),
        .init(code: "ms", displayName: "Malay",       nativeName: "Bahasa Melayu"),
        .init(code: "ml", displayName: "Malayalam",   nativeName: "മലയാളം"),
        .init(code: "mt", displayName: "Maltese",     nativeName: "Malti"),
        .init(code: "mr", displayName: "Marathi",     nativeName: "मराठी"),
        .init(code: "no", displayName: "Norwegian",   nativeName: "Norsk"),
        .init(code: "fa", displayName: "Persian",     nativeName: "فارسی"),
        .init(code: "pl", displayName: "Polish",      nativeName: "Polski"),
        .init(code: "pt", displayName: "Portuguese",  nativeName: "Português"),
        .init(code: "pa", displayName: "Punjabi",     nativeName: "ਪੰਜਾਬੀ"),
        .init(code: "ro", displayName: "Romanian",    nativeName: "Română"),
        .init(code: "ru", displayName: "Russian",     nativeName: "Русский"),
        .init(code: "sr", displayName: "Serbian",     nativeName: "Српски"),
        .init(code: "sk", displayName: "Slovak",      nativeName: "Slovenčina"),
        .init(code: "sl", displayName: "Slovenian",   nativeName: "Slovenščina"),
        .init(code: "es", displayName: "Spanish",     nativeName: "Español"),
        .init(code: "sw", displayName: "Swahili",     nativeName: "Kiswahili"),
        .init(code: "sv", displayName: "Swedish",     nativeName: "Svenska"),
        .init(code: "tl", displayName: "Tagalog",     nativeName: nil),
        .init(code: "ta", displayName: "Tamil",       nativeName: "தமிழ்"),
        .init(code: "te", displayName: "Telugu",      nativeName: "తెలుగు"),
        .init(code: "th", displayName: "Thai",        nativeName: "ไทย"),
        .init(code: "tr", displayName: "Turkish",     nativeName: "Türkçe"),
        .init(code: "uk", displayName: "Ukrainian",   nativeName: "Українська"),
        .init(code: "ur", displayName: "Urdu",        nativeName: "اردو"),
        .init(code: "vi", displayName: "Vietnamese",  nativeName: "Tiếng Việt"),
        .init(code: "cy", displayName: "Welsh",       nativeName: "Cymraeg"),
    ]

    /// Lookup helper. `nil` for codes we don't recognise (e.g. an old
    /// preference set when we shipped fewer languages, or a manually-edited
    /// UserDefaults value). Caller decides whether to fall back to auto.
    static func language(for code: String) -> TranscriptionLanguage? {
        if code == TranscriptionLanguageMode.autoCode { return auto }
        return supported.first { $0.code == code }
    }

    /// True if `code` is one of our curated languages OR the auto sentinel.
    /// Used by PreferencesStore to validate persisted state on init.
    static func isValid(_ code: String) -> Bool {
        language(for: code) != nil
    }
}

/// The complete set of language codes Whisper's tokenizer accepts. Sourced
/// from `whisper/tokenizer.py` `LANGUAGES` dict in `openai/whisper`
/// (cross-checked 2026-05-09). 99 entries.
///
/// We curate a smaller subset for the picker — see
/// `TranscriptionLanguageCatalog.supported`. This set exists so we can
/// (a) reject UserDefaults garbage at the persistence boundary, and
/// (b) unit-test that every code we ship in our curated catalog is
/// actually a valid Whisper code (no typos, no codes that have been
/// deprecated, no aspirational additions ahead of upstream).
enum WhisperOfficialLanguages {
    /// Every code Whisper's `LANGUAGES` dict maps from. Lowercase ISO 639-1
    /// for most; Whisper-specific codes for a few (e.g. `yue` Cantonese,
    /// `haw` Hawaiian, `jw` Javanese — which is `jv` in ISO 639-1 but
    /// Whisper kept the older `jw`).
    static let codes: Set<String> = [
        "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr",
        "pl", "ca", "nl", "ar", "sv", "it", "id", "hi", "fi", "vi",
        "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no",
        "th", "ur", "hr", "bg", "lt", "la", "mi", "ml", "cy", "sk",
        "te", "fa", "lv", "bn", "sr", "az", "sl", "kn", "et", "mk",
        "br", "eu", "is", "hy", "ne", "mn", "bs", "kk", "sq", "sw",
        "gl", "mr", "pa", "si", "km", "sn", "yo", "so", "af", "oc",
        "ka", "be", "tg", "sd", "gu", "am", "yi", "lo", "uz", "fo",
        "ht", "ps", "tk", "nn", "mt", "sa", "lb", "my", "bo", "tl",
        "mg", "as", "tt", "haw", "ln", "ha", "ba", "jw", "su", "yue",
    ]

    /// Convenience predicate; matches the `codes` Set.
    static func contains(_ code: String) -> Bool { codes.contains(code) }
}
