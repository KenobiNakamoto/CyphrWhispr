import XCTest
@testable import CyphrWhispr

/// Unit tests for the Polish (Apple Foundation Models cleanup) feature.
///
/// We deliberately don't drive `LanguageModelSession` directly — those tests
/// would be flaky (depends on macOS 26+, Apple Intelligence enabled, model
/// downloaded) and the real LM is non-deterministic anyway. Instead we cover:
///
///   1. `CleanupPrompt` constants — the default prompt is non-empty and the
///      EMPTY sentinel is wired correctly.
///   2. `FoundationModelsCleaner.validate(...)` — the length-ratio heuristic
///      and EMPTY-sentinel handling, which is the only non-trivial logic
///      that runs on the LM's output.
///   3. `FoundationModelsCleaner.format(timeout:)` — the "3s vs 3.5s"
///      formatter feeding the rejected-reason logs.
///   4. The cleaner's `clean(...)` short-circuit paths — empty input, polish
///      disabled — both of which run without touching the LM.
///   5. The `MockTranscriptionCleaner` itself, since AppCoordinator integration
///      tests will lean on it later.
final class CleanupPromptTests: XCTestCase {
    func testDefaultPromptHasContent() {
        XCTAssertFalse(CleanupPrompt.defaultPrompt.isEmpty)
        // Spot-check: the default prompt should mention the EMPTY sentinel
        // by name so the model knows the output contract.
        XCTAssertTrue(CleanupPrompt.defaultPrompt.contains(CleanupPrompt.emptySentinel))
    }

    func testEmptySentinel() {
        XCTAssertEqual(CleanupPrompt.emptySentinel, "EMPTY")
    }

    func testSystemMessagePassthrough() {
        // Currently a passthrough; this test will start failing the moment we
        // add boilerplate (custom-vocabulary section, model guard rails) so
        // we'll know to update it deliberately.
        let composed = CleanupPrompt.systemMessage(effective: "test")
        XCTAssertEqual(composed, "test")
    }
}

final class FoundationModelsCleanerValidateTests: XCTestCase {
    func testValidateAcceptsCleanedTextOfReasonableLength() {
        let raw = "um so i was thinking maybe we could ship on friday"  // 51 chars
        let cleaned = "I was thinking maybe we could ship on Friday."     // 47 chars
        let outcome = FoundationModelsCleaner.validate(raw: raw, cleaned: cleaned)
        guard case .cleaned(let text) = outcome else {
            return XCTFail("expected .cleaned, got \(outcome)")
        }
        XCTAssertEqual(text, cleaned)
    }

    func testValidateTrimsWhitespace() {
        let raw = "hello world"
        let cleaned = "  Hello, world.  \n"
        let outcome = FoundationModelsCleaner.validate(raw: raw, cleaned: cleaned)
        guard case .cleaned(let text) = outcome else {
            return XCTFail("expected .cleaned, got \(outcome)")
        }
        XCTAssertEqual(text, "Hello, world.")
    }

    func testValidateMapsEmptySentinelToEmpty() {
        let outcome = FoundationModelsCleaner.validate(raw: "anything", cleaned: "EMPTY")
        XCTAssertEqual(outcome, .empty)
    }

    func testValidateMapsEmptySentinelWithSurroundingWhitespace() {
        let outcome = FoundationModelsCleaner.validate(raw: "anything", cleaned: "\n EMPTY \n")
        XCTAssertEqual(outcome, .empty)
    }

    func testValidateRejectsTooShortOutput() {
        // 100 → 30 chars = ratio 0.3, below the 0.4 floor.
        let raw = String(repeating: "a", count: 100)
        let cleaned = String(repeating: "b", count: 30)
        let outcome = FoundationModelsCleaner.validate(raw: raw, cleaned: cleaned)
        if case .rejected = outcome { return }
        XCTFail("expected .rejected, got \(outcome)")
    }

    func testValidateRejectsTooLongOutput() {
        // 20 → 100 chars = ratio 5.0, well above the 2.5 ceiling.
        let raw = String(repeating: "a", count: 20)
        let cleaned = String(repeating: "b", count: 100)
        let outcome = FoundationModelsCleaner.validate(raw: raw, cleaned: cleaned)
        if case .rejected = outcome { return }
        XCTFail("expected .rejected, got \(outcome)")
    }

    func testValidateRejectsEmptyOutput() {
        let outcome = FoundationModelsCleaner.validate(raw: "hello", cleaned: "   ")
        if case .rejected = outcome { return }
        XCTFail("expected .rejected for empty cleaned output, got \(outcome)")
    }

    func testValidateAcceptsRatioAtBoundary() {
        // 50 chars → 25 chars = ratio 0.5, well within bounds.
        let raw = String(repeating: "a", count: 50)
        let cleaned = String(repeating: "b", count: 25)
        let outcome = FoundationModelsCleaner.validate(raw: raw, cleaned: cleaned)
        if case .cleaned = outcome { return }
        XCTFail("expected .cleaned at boundary 0.5x, got \(outcome)")
    }
}

final class FoundationModelsCleanerFormatTests: XCTestCase {
    func testFormatIntegerSeconds() {
        XCTAssertEqual(FoundationModelsCleaner.format(timeout: 3), "3s")
        XCTAssertEqual(FoundationModelsCleaner.format(timeout: 10), "10s")
    }

    func testFormatFractionalSeconds() {
        XCTAssertEqual(FoundationModelsCleaner.format(timeout: 3.5), "3.5s")
        XCTAssertEqual(FoundationModelsCleaner.format(timeout: 0.25), "0.3s")
    }
}

final class FoundationModelsCleanerShortCircuitTests: XCTestCase {
    /// Empty input should bail before the LM call, regardless of OS support.
    /// Confirms the cheap-fast-path path inside `clean(...)` works on every
    /// developer's machine, not just macOS 26 ones.
    func testCleanReturnsEmptyForEmptyInput() async {
        let cleaner = FoundationModelsCleaner()
        let availability = await cleaner.availability()

        let outcome = await cleaner.clean("", prompt: "ignored", timeout: 1.0)
        switch outcome {
        case .empty:
            return  // expected on macOS 26+
        case .skipped(let reason):
            // macOS <26: short-circuit happens after the availability check, so
            // skipped is the right answer. Either branch is fine — the point
            // is we didn't hang on an LM call we can't make.
            XCTAssertNotEqual(availability, .available)
            XCTAssertEqual(reason, availability)
        default:
            XCTFail("expected .empty or .skipped, got \(outcome)")
        }
    }

    func testCleanReturnsEmptyForWhitespaceInput() async {
        let cleaner = FoundationModelsCleaner()
        let availability = await cleaner.availability()

        let outcome = await cleaner.clean("   \n\t  ", prompt: "ignored", timeout: 1.0)
        switch outcome {
        case .empty:
            return
        case .skipped(let reason):
            XCTAssertNotEqual(availability, .available)
            XCTAssertEqual(reason, availability)
        default:
            XCTFail("expected .empty or .skipped, got \(outcome)")
        }
    }
}

/// Test double — never calls the real `LanguageModelSession`, returns whatever
/// the test set up. Exercises the AppCoordinator integration paths without
/// requiring macOS 26 + Apple Intelligence.
final class MockTranscriptionCleaner: TranscriptionCleaner, @unchecked Sendable {
    var stubbedAvailability: PolishAvailability = .available
    var stubbedOutcome: PolishOutcome = .cleaned("polished")
    var lastPrompt: String?
    var lastRaw: String?
    var lastTimeout: TimeInterval?
    /// Artificial delay before returning, to exercise timeout races. Use a
    /// value larger than the caller's timeout to simulate a slow LM.
    var simulatedDelay: TimeInterval = 0

    func availability() async -> PolishAvailability { stubbedAvailability }

    func clean(_ raw: String, prompt: String, timeout: TimeInterval) async -> PolishOutcome {
        lastRaw = raw
        lastPrompt = prompt
        lastTimeout = timeout
        if simulatedDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))
        }
        return stubbedOutcome
    }
}

final class MockTranscriptionCleanerTests: XCTestCase {
    func testMockReturnsStubbedOutcome() async {
        let mock = MockTranscriptionCleaner()
        mock.stubbedOutcome = .cleaned("hello, world")
        let outcome = await mock.clean("hello world", prompt: "p", timeout: 1)
        XCTAssertEqual(outcome, .cleaned("hello, world"))
        XCTAssertEqual(mock.lastRaw, "hello world")
        XCTAssertEqual(mock.lastPrompt, "p")
        XCTAssertEqual(mock.lastTimeout, 1)
    }

    func testMockReturnsRejected() async {
        let mock = MockTranscriptionCleaner()
        mock.stubbedOutcome = .rejected(reason: "test")
        let outcome = await mock.clean("input", prompt: "p", timeout: 1)
        XCTAssertEqual(outcome, .rejected(reason: "test"))
    }
}

@MainActor
final class PreferencesStorePolishTests: XCTestCase {
    /// Snapshot the singleton's polish state at the start of each test so we
    /// can restore it in tearDown — `PreferencesStore.shared` is a process-
    /// wide singleton backed by UserDefaults, and bleed between tests would
    /// flake on whichever happened to run last.
    private var savedEnabled: Bool!
    private var savedCustomised: Bool!
    private var savedCustomPrompt: String!

    override func setUp() {
        super.setUp()
        let prefs = PreferencesStore.shared
        savedEnabled = prefs.polishEnabled
        savedCustomised = prefs.polishPromptIsCustomised
        savedCustomPrompt = prefs.polishCustomPrompt
    }

    override func tearDown() {
        let prefs = PreferencesStore.shared
        prefs.polishEnabled = savedEnabled
        prefs.polishPromptIsCustomised = savedCustomised
        prefs.polishCustomPrompt = savedCustomPrompt
        super.tearDown()
    }

    func testEffectivePromptUsesDefaultWhenNotCustomised() {
        let prefs = PreferencesStore.shared
        prefs.polishPromptIsCustomised = false
        // The custom prompt slot might hold a stale user edit from a previous
        // session — when not customised, the effective prompt should still
        // come from CleanupPrompt.defaultPrompt regardless.
        prefs.polishCustomPrompt = "stale user edits should be ignored"
        XCTAssertEqual(prefs.effectivePolishPrompt, CleanupPrompt.defaultPrompt)
    }

    func testEffectivePromptUsesCustomWhenCustomised() {
        let prefs = PreferencesStore.shared
        prefs.polishCustomPrompt = "my custom prompt"
        prefs.polishPromptIsCustomised = true
        XCTAssertEqual(prefs.effectivePolishPrompt, "my custom prompt")
    }

    func testEnableCustomPromptSeedsTextWithDefault() {
        let prefs = PreferencesStore.shared
        prefs.polishPromptIsCustomised = false
        prefs.polishCustomPrompt = ""
        prefs.enablePolishCustomPrompt()
        XCTAssertTrue(prefs.polishPromptIsCustomised)
        XCTAssertEqual(prefs.polishCustomPrompt, CleanupPrompt.defaultPrompt)
    }

    func testResetPolishPromptKeepsLastEdits() {
        let prefs = PreferencesStore.shared
        prefs.polishCustomPrompt = "user's careful tuning, do not lose"
        prefs.polishPromptIsCustomised = true
        prefs.resetPolishPrompt()
        XCTAssertFalse(prefs.polishPromptIsCustomised)
        // Critical — flipping out of customised mode keeps the user's last
        // edits so re-customising restores them rather than wiping the slate.
        XCTAssertEqual(prefs.polishCustomPrompt, "user's careful tuning, do not lose")
    }
}
