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
    static let supported: [TranscriptionLanguage] = [
        .init(code: "en", displayName: "English",     nativeName: nil),
        .init(code: "ar", displayName: "Arabic",      nativeName: "العربية"),
        .init(code: "bn", displayName: "Bengali",     nativeName: "বাংলা"),
        .init(code: "ca", displayName: "Catalan",     nativeName: "Català"),
        .init(code: "yue", displayName: "Cantonese",  nativeName: "粵語"),
        .init(code: "zh", displayName: "Chinese",     nativeName: "中文"),
        .init(code: "cs", displayName: "Czech",       nativeName: "Čeština"),
        .init(code: "da", displayName: "Danish",      nativeName: "Dansk"),
        .init(code: "nl", displayName: "Dutch",       nativeName: "Nederlands"),
        .init(code: "fi", displayName: "Finnish",     nativeName: "Suomi"),
        .init(code: "fr", displayName: "French",      nativeName: "Français"),
        .init(code: "de", displayName: "German",      nativeName: "Deutsch"),
        .init(code: "el", displayName: "Greek",       nativeName: "Ελληνικά"),
        .init(code: "he", displayName: "Hebrew",      nativeName: "עברית"),
        .init(code: "hi", displayName: "Hindi",       nativeName: "हिन्दी"),
        .init(code: "hu", displayName: "Hungarian",   nativeName: "Magyar"),
        .init(code: "id", displayName: "Indonesian",  nativeName: "Bahasa Indonesia"),
        .init(code: "it", displayName: "Italian",     nativeName: "Italiano"),
        .init(code: "ja", displayName: "Japanese",    nativeName: "日本語"),
        .init(code: "ko", displayName: "Korean",      nativeName: "한국어"),
        .init(code: "ms", displayName: "Malay",       nativeName: "Bahasa Melayu"),
        .init(code: "no", displayName: "Norwegian",   nativeName: "Norsk"),
        .init(code: "fa", displayName: "Persian",     nativeName: "فارسی"),
        .init(code: "pl", displayName: "Polish",      nativeName: "Polski"),
        .init(code: "pt", displayName: "Portuguese",  nativeName: "Português"),
        .init(code: "ro", displayName: "Romanian",    nativeName: "Română"),
        .init(code: "ru", displayName: "Russian",     nativeName: "Русский"),
        .init(code: "es", displayName: "Spanish",     nativeName: "Español"),
        .init(code: "sv", displayName: "Swedish",     nativeName: "Svenska"),
        .init(code: "th", displayName: "Thai",        nativeName: "ไทย"),
        .init(code: "tr", displayName: "Turkish",     nativeName: "Türkçe"),
        .init(code: "uk", displayName: "Ukrainian",   nativeName: "Українська"),
        .init(code: "vi", displayName: "Vietnamese",  nativeName: "Tiếng Việt"),
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
