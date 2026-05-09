import XCTest
@testable import CyphrWhispr

/// Tests for the language data model + the catalog. The actor-level
/// session-locking logic lives inside `WhisperKitBackend` and depends on
/// a real WhisperKit pipeline; not mocked here.
final class TranscriptionLanguageTests: XCTestCase {

    // MARK: - TranscriptionLanguageMode

    func testModeFromAutoSentinelString() {
        XCTAssertEqual(TranscriptionLanguageMode.from(persistedCode: "auto"),
                       .autoDetect)
    }

    func testModeFromLanguageCode() {
        XCTAssertEqual(TranscriptionLanguageMode.from(persistedCode: "es"),
                       .forced(code: "es"))
    }

    func testModeFromNilOrEmptyDefaultsToAuto() {
        XCTAssertEqual(TranscriptionLanguageMode.from(persistedCode: nil),
                       .autoDetect)
        XCTAssertEqual(TranscriptionLanguageMode.from(persistedCode: ""),
                       .autoDetect)
    }

    func testPersistedCodeRoundTrip() {
        for code in ["en", "es", "ja", "yue", TranscriptionLanguageMode.autoCode] {
            let mode = TranscriptionLanguageMode.from(persistedCode: code)
            XCTAssertEqual(mode.persistedCode, code,
                           "round-trip failed for \(code)")
        }
    }

    func testEnglishOnlyPersistsAsEn() {
        // The englishOnly view-model state and forced("en") share the
        // wire format. Lock that in so a future refactor can't accidentally
        // emit something else and break existing UserDefaults.
        XCTAssertEqual(TranscriptionLanguageMode.englishOnly.persistedCode, "en")
    }

    // MARK: - TranscriptionLanguageCatalog

    func testAutoIsValid() {
        XCTAssertTrue(TranscriptionLanguageCatalog.isValid(TranscriptionLanguageMode.autoCode))
    }

    func testEnglishIsFirstInSupportedList() {
        // English-first sort is intentional — most common pick goes
        // straight to the top of the menu after the auto entry.
        XCTAssertEqual(TranscriptionLanguageCatalog.supported.first?.code, "en")
    }

    func testAllCuratedCodesAreValid() {
        for lang in TranscriptionLanguageCatalog.supported {
            XCTAssertTrue(TranscriptionLanguageCatalog.isValid(lang.code),
                          "\(lang.code) should be valid")
        }
    }

    func testUnknownCodeIsInvalid() {
        XCTAssertFalse(TranscriptionLanguageCatalog.isValid("xx"))
        XCTAssertFalse(TranscriptionLanguageCatalog.isValid(""))
    }

    func testCuratedCodesAreUnique() {
        let codes = TranscriptionLanguageCatalog.supported.map(\.code)
        XCTAssertEqual(codes.count, Set(codes).count,
                       "duplicate language codes in catalog")
    }

    func testCommonLanguagesArePresent() {
        // Smoke test: a regression that drops one of these is almost
        // certainly a bug.
        let mustHave = ["en", "es", "fr", "de", "it", "pt", "ja", "ko",
                        "zh", "ar", "ru", "hi", "nl", "sv", "tr"]
        for code in mustHave {
            XCTAssertNotNil(TranscriptionLanguageCatalog.language(for: code),
                            "expected curated language: \(code)")
        }
    }

    /// Pinned set of languages CyphrWhispr explicitly commits to supporting.
    /// Driven by an early product requirement: Spanish, German, Catalan and
    /// English are the founding-user must-haves; the rest (major European,
    /// Arabic, Chinese, Japanese) reflect the v1 audience scope. A failure
    /// here means we shipped a build that visibly drops one of these from
    /// the picker — block it.
    func testProductRequiredLanguagesAllPresent() {
        let required: [(String, String)] = [
            // Founding-user core — must be in every release
            ("en", "English"),
            ("es", "Spanish"),
            ("de", "German"),
            ("ca", "Catalan"),
            // Major European
            ("fr", "French"),
            ("it", "Italian"),
            ("pt", "Portuguese"),
            ("nl", "Dutch"),
            ("pl", "Polish"),
            ("ru", "Russian"),
            ("uk", "Ukrainian"),
            ("sv", "Swedish"),
            ("no", "Norwegian"),
            ("da", "Danish"),
            ("fi", "Finnish"),
            ("cs", "Czech"),
            ("sk", "Slovak"),
            ("hu", "Hungarian"),
            ("ro", "Romanian"),
            ("bg", "Bulgarian"),
            ("hr", "Croatian"),
            ("sr", "Serbian"),
            ("sl", "Slovenian"),
            ("bs", "Bosnian"),
            ("el", "Greek"),
            ("tr", "Turkish"),
            ("lt", "Lithuanian"),
            ("lv", "Latvian"),
            ("et", "Estonian"),
            // Major non-European
            ("ar", "Arabic"),
            ("zh", "Chinese"),
            ("yue", "Cantonese"),
            ("ja", "Japanese"),
            ("ko", "Korean"),
            ("hi", "Hindi"),
            ("he", "Hebrew"),
        ]
        for (code, expectedName) in required {
            let lang = TranscriptionLanguageCatalog.language(for: code)
            XCTAssertNotNil(lang,
                            "REQUIRED language missing from picker: \(expectedName) (\(code))")
            XCTAssertEqual(lang?.displayName, expectedName,
                           "Display name for \(code) should be '\(expectedName)' (got '\(lang?.displayName ?? "nil")')")
        }
    }

    /// Defends against typos in our curated catalog — every code we ship
    /// MUST be one Whisper actually accepts at decode time. Without this
    /// guard a typo (`"ge"` instead of `"de"`) would make it through code
    /// review, get into UserDefaults on user machines, and silently break
    /// transcription only for users who picked that bad code.
    func testEveryCuratedCodeIsAValidWhisperCode() {
        for lang in TranscriptionLanguageCatalog.supported {
            XCTAssertTrue(
                WhisperOfficialLanguages.contains(lang.code),
                "curated code '\(lang.code)' (\(lang.displayName)) is NOT in Whisper's tokenizer LANGUAGES dict — typo or aspirational addition?"
            )
        }
    }

    func testWhisperOfficialLanguagesHasExpectedCount() {
        // Sanity check on the source-of-truth set — Whisper's tokenizer
        // ships exactly 100 languages as of 2026-05-09 (99 in the original
        // Whisper paper plus Cantonese `yue`, added later).
        // A change here means either we mis-typed the constant or upstream
        // Whisper added / removed languages — either way, worth a deliberate
        // look rather than silently slipping by.
        XCTAssertEqual(WhisperOfficialLanguages.codes.count, 100)
    }

    func testWhisperOfficialLanguagesIncludesAutoSentinelHandling() {
        // The auto sentinel is NOT a Whisper language code — it's our own
        // user-facing string. Make sure we never accidentally bake it in
        // to the official set.
        XCTAssertFalse(WhisperOfficialLanguages.contains(TranscriptionLanguageMode.autoCode))
    }

    func testNativeNameOmittedForEnglish() {
        // English is its own native name; rendering "English — English" in
        // the picker would be silly. The picker treats nil nativeName as
        // "no subtitle".
        let english = TranscriptionLanguageCatalog.language(for: "en")
        XCTAssertNil(english?.nativeName)
    }

    func testNativeNamePresentForNonEnglishCommonLanguages() {
        // Spot-check a few — ensures we didn't ship the catalog with
        // empty native names for languages users will actually pick.
        XCTAssertEqual(TranscriptionLanguageCatalog.language(for: "es")?.nativeName, "Español")
        XCTAssertEqual(TranscriptionLanguageCatalog.language(for: "ja")?.nativeName, "日本語")
        XCTAssertEqual(TranscriptionLanguageCatalog.language(for: "zh")?.nativeName, "中文")
    }

    // MARK: - PreferencesStore.effectiveLanguageCode

    @MainActor
    func testEffectiveLanguageCode_englishOnlyModelForcesEnglish() {
        // Setup: sneak the selectedLanguageCode + activeModelID into UserDefaults
        // BEFORE PreferencesStore is touched, so init reads our test values.
        // We can't reset the singleton from a test, so this only works on a
        // fresh test process — which xcodebuild gives us.
        let prefs = PreferencesStore.shared

        let originalLang = prefs.selectedLanguageCode
        let originalModel = prefs.activeModelID
        defer {
            prefs.selectedLanguageCode = originalLang
            prefs.activeModelID = originalModel
        }

        // Pick an English-only model + try to set Spanish.
        prefs.activeModelID = "openai_whisper-small.en"
        prefs.selectedLanguageCode = "es"

        XCTAssertEqual(prefs.effectiveLanguageCode, "en",
                       "English-only model must clamp the language to en regardless of the user's pick")
        XCTAssertFalse(prefs.activeModelSupportsLanguageChoice)
    }

    @MainActor
    func testEffectiveLanguageCode_multilingualModelHonoursPick() {
        let prefs = PreferencesStore.shared

        let originalLang = prefs.selectedLanguageCode
        let originalModel = prefs.activeModelID
        defer {
            prefs.selectedLanguageCode = originalLang
            prefs.activeModelID = originalModel
        }

        prefs.activeModelID = "openai_whisper-large-v3-v20240930_turbo"
        prefs.selectedLanguageCode = "es"

        XCTAssertEqual(prefs.effectiveLanguageCode, "es")
        XCTAssertTrue(prefs.activeModelSupportsLanguageChoice)
    }

    @MainActor
    func testEffectiveLanguageCode_autoOnMultilingualPassesThrough() {
        let prefs = PreferencesStore.shared

        let originalLang = prefs.selectedLanguageCode
        let originalModel = prefs.activeModelID
        defer {
            prefs.selectedLanguageCode = originalLang
            prefs.activeModelID = originalModel
        }

        prefs.activeModelID = "openai_whisper-large-v3-v20240930_turbo"
        prefs.selectedLanguageCode = TranscriptionLanguageMode.autoCode

        XCTAssertEqual(prefs.effectiveLanguageCode, TranscriptionLanguageMode.autoCode)
    }

    // MARK: - ModelCatalog smoke (the multilingual additions)

    func testModelCatalogIncludesMultilingualSmall() {
        let small = ModelCatalog.model(id: "openai_whisper-small")
        XCTAssertNotNil(small, "multilingual small variant must be in catalog")
        XCTAssertTrue(small?.isMultilingual ?? false)
    }

    func testModelCatalogIncludesMultilingualMedium() {
        let medium = ModelCatalog.model(id: "openai_whisper-medium")
        XCTAssertNotNil(medium, "multilingual medium variant must be in catalog")
        XCTAssertTrue(medium?.isMultilingual ?? false)
    }

    func testEnglishVariantsAreNotMarkedMultilingual() {
        for id in ["openai_whisper-tiny.en", "openai_whisper-base.en",
                   "openai_whisper-small.en", "openai_whisper-medium.en"] {
            let model = ModelCatalog.model(id: id)
            XCTAssertNotNil(model, "expected catalog entry: \(id)")
            XCTAssertFalse(model?.isMultilingual ?? true,
                           "\(id) should be English-only")
        }
    }
}
