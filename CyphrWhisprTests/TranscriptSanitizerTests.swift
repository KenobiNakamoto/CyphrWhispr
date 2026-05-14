import XCTest
@testable import CyphrWhispr

/// Coverage for `TranscriptSanitizer.clean` across the three artifact classes
/// it strips (special tokens, all-caps bracketed labels, parenthesised noise
/// labels) plus negative cases proving legitimate user dictation passes
/// through unchanged.
final class TranscriptSanitizerTests: XCTestCase {

    // MARK: Real-world regression fixture
    //
    // Exact output the user pasted into the issue report on 2026-05-08 when
    // dictating into a fresh-install English-only model. All three artifact
    // classes are present in this single string — once this passes we have
    // basic confidence the sanitizer covers the leak surface.

    func testRealWorldFreshInstallNoise_isFullyStripped() {
        let raw = """
        <|startoftranscript|><|0.00|> [NON-ENGLISH SPEECH]<|3.36|><|endoftext|> \
        <|startoftranscript|><|0.00|> (speaking in foreign language)<|3.92|><|endoftext|> \
        <|startoftranscript|><|0.00|> (speaking in foreign language)<|3.92|><|endoftext|> \
        (speaking in foreign language)
        """
        XCTAssertEqual(TranscriptSanitizer.clean(raw), "")
    }

    // MARK: Special tokens (<|...|>)

    func testSpecialTokens_areStripped() {
        XCTAssertEqual(
            TranscriptSanitizer.clean("<|startoftranscript|>hello world<|endoftext|>"),
            "hello world"
        )
    }

    func testTimestampTokens_areStripped() {
        XCTAssertEqual(
            TranscriptSanitizer.clean("<|0.00|>hello<|3.36|> world<|6.20|>"),
            "hello world"
        )
    }

    func testLanguageTag_isStripped() {
        XCTAssertEqual(
            TranscriptSanitizer.clean("<|en|>hello world"),
            "hello world"
        )
    }

    // MARK: Bracketed labels

    func testAllCapsBracketLabel_isStripped() {
        XCTAssertEqual(
            TranscriptSanitizer.clean("hello [BLANK_AUDIO] world"),
            "hello world"
        )
    }

    func testHyphenatedAllCapsBracketLabel_isStripped() {
        // The original sanitizer's regex rejected the hyphen, letting this
        // through. Pinning a test so it stays stripped.
        XCTAssertEqual(
            TranscriptSanitizer.clean("hello [NON-ENGLISH SPEECH] world"),
            "hello world"
        )
    }

    func testCommonNoiseBracketLabels_areStripped() {
        let cases = [
            "[MUSIC]", "[NOISE]", "[INAUDIBLE]", "[SILENCE]",
            "[BLANK_AUDIO]", "[FOREIGN_LANGUAGE]",
        ]
        for label in cases {
            XCTAssertEqual(
                TranscriptSanitizer.clean("hello \(label) world"),
                "hello world",
                "expected \(label) to be stripped"
            )
        }
    }

    func testMixedCaseBracket_isPreserved() {
        // The user dictating prose like "see [appendix]" should not be eaten.
        XCTAssertEqual(
            TranscriptSanitizer.clean("see [appendix] for details"),
            "see [appendix] for details"
        )
    }

    func testTitleCaseBracket_isPreserved() {
        XCTAssertEqual(
            TranscriptSanitizer.clean("the [Note] field"),
            "the [Note] field"
        )
    }

    // MARK: Parenthesised noise labels

    func testSpeakingInForeignLanguage_isStripped() {
        XCTAssertEqual(
            TranscriptSanitizer.clean("(speaking in foreign language)"),
            ""
        )
    }

    func testSpeakingInSpecificLanguage_isStripped() {
        // The pattern "speaking in [^)]*" should match any language.
        XCTAssertEqual(
            TranscriptSanitizer.clean("hello (speaking in Spanish) world"),
            "hello world"
        )
    }

    func testCommonParenNoiseLabels_areStripped() {
        let cases = [
            "(music)", "(applause)", "(laughter)", "(silence)",
            "(no speech)", "(inaudible)", "(unintelligible)",
            "(background noise)", "(coughing)", "(breathing)",
        ]
        for label in cases {
            XCTAssertEqual(
                TranscriptSanitizer.clean("hello \(label) world"),
                "hello world",
                "expected \(label) to be stripped"
            )
        }
    }

    func testNoiseLabelsAreCaseInsensitive() {
        XCTAssertEqual(
            TranscriptSanitizer.clean("(MUSIC)"),
            ""
        )
        XCTAssertEqual(
            TranscriptSanitizer.clean("(Speaking in Foreign Language)"),
            ""
        )
    }

    func testUserParentheticalAside_isPreserved() {
        // Dictation like "(see page 12)" must pass through — the allowlist
        // approach is the whole reason for this design.
        XCTAssertEqual(
            TranscriptSanitizer.clean("the answer (see page 12) is yes"),
            "the answer (see page 12) is yes"
        )
    }

    func testUserParentheticalWithRandomWord_isPreserved() {
        XCTAssertEqual(
            TranscriptSanitizer.clean("hello (world) goodbye"),
            "hello (world) goodbye"
        )
    }

    // MARK: Whitespace + edge cases

    func testCollapsesMultipleSpacesAfterStripping() {
        XCTAssertEqual(
            TranscriptSanitizer.clean("hello   [MUSIC]   world"),
            "hello world"
        )
    }

    func testTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(
            TranscriptSanitizer.clean("   hello world   "),
            "hello world"
        )
    }

    func testEmptyInput_returnsEmpty() {
        XCTAssertEqual(TranscriptSanitizer.clean(""), "")
    }

    func testNoArtifacts_passesThroughUnchanged() {
        let clean = "The quick brown fox jumps over the lazy dog."
        XCTAssertEqual(TranscriptSanitizer.clean(clean), clean)
    }
}
