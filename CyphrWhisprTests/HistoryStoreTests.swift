import XCTest
import CryptoKit
@testable import CyphrWhispr

/// Round-trip, persistence, retention, search, and encryption-at-rest
/// coverage for the SQLCipher-backed `HistoryStore`.
///
/// Each test runs against a throwaway vault in the temp directory, created
/// fresh in `setUp` and deleted in `tearDown`. `HistoryStore` is an `actor`,
/// so every call crosses the actor boundary and is `await`ed; awaited values
/// are bound to a `let` before assertion because `XCTAssert*` autoclosures
/// are synchronous.
final class HistoryStoreTests: XCTestCase {

    /// Two valid but different BIP-39 phrases. `mnemonicA` opens the vault in
    /// every test; `mnemonicB` is the "wrong key" in the rejection test.
    private let mnemonicA = "abandon abandon abandon abandon abandon abandon "
        + "abandon abandon abandon abandon abandon about"
    private let mnemonicB = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong"

    private var vaultURL: URL!

    override func setUp() {
        super.setUp()
        vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cyphrwhispr-test-\(UUID().uuidString).db")
    }

    override func tearDown() {
        if let vaultURL { try? FileManager.default.removeItem(at: vaultURL) }
        vaultURL = nil
        super.tearDown()
    }

    /// Pause so the next `insert`'s `Date()` is strictly later — keeps
    /// newest-first ordering assertions deterministic.
    private func tick() async throws {
        try await Task.sleep(nanoseconds: 6_000_000)   // 6 ms
    }

    // MARK: - Round-trip

    func testInsertThenRecent_returnsNewestFirst() async throws {
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        try await store.insert(text: "first", sourceApp: "TextEdit")
        try await tick()
        try await store.insert(text: "second", sourceApp: nil)

        let recent = try await store.recent()
        XCTAssertEqual(recent.map(\.text), ["second", "first"])
        XCTAssertNil(recent[0].sourceApp)
        XCTAssertEqual(recent[1].sourceApp, "TextEdit")
        XCTAssertEqual(recent[1].charCount, 5)
    }

    func testCount_tracksInserts() async throws {
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        let initialCount = try await store.count()
        XCTAssertEqual(initialCount, 0)

        for index in 0..<4 {
            try await store.insert(text: "entry \(index)", sourceApp: nil)
        }
        let finalCount = try await store.count()
        XCTAssertEqual(finalCount, 4)
    }

    func testClearAll_emptiesTheVault() async throws {
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        for index in 0..<3 {
            try await store.insert(text: "entry \(index)", sourceApp: nil)
        }
        try await store.clearAll()

        let count = try await store.count()
        XCTAssertEqual(count, 0)
        let recent = try await store.recent()
        XCTAssertTrue(recent.isEmpty)
    }

    // MARK: - Persistence across reopen

    func testVaultPersists_acrossReopenWithSamePhrase() async throws {
        do {
            let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
            try await store.insert(text: "persisted entry", sourceApp: "Notes")
        }
        // The first store is released here; its connection is closed.
        let reopened = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        let recent = try await reopened.recent()
        XCTAssertEqual(recent.map(\.text), ["persisted entry"])
    }

    func testReopenWithWrongPhrase_throwsWrongKey() async throws {
        do {
            let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
            try await store.insert(text: "secret", sourceApp: nil)
        }
        // `HistoryStore.init` is a synchronous throwing initializer, so this
        // assertion needs no `await`.
        XCTAssertThrowsError(
            try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicB)
        ) { error in
            XCTAssertEqual(error as? HistoryStoreError, .wrongKey)
        }
    }

    // MARK: - Retention

    func testPruneMaxEntries_keepsNewest() async throws {
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        for index in 0..<5 {
            try await store.insert(text: "entry \(index)", sourceApp: nil)
            try await tick()
        }
        let removed = try await store.prune(policy: .maxEntries(2))
        XCTAssertEqual(removed, 3)

        let recent = try await store.recent()
        XCTAssertEqual(recent.map(\.text), ["entry 4", "entry 3"])
    }

    func testPruneKeepForever_isNoOp() async throws {
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        for index in 0..<3 {
            try await store.insert(text: "entry \(index)", sourceApp: nil)
        }
        let removed = try await store.prune(policy: .keepForever)
        XCTAssertEqual(removed, 0)

        let count = try await store.count()
        XCTAssertEqual(count, 3)
    }

    func testPruneMaxAge_removesEntriesOlderThanCutoff() async throws {
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        for index in 0..<3 {
            try await store.insert(text: "entry \(index)", sourceApp: nil)
        }
        try await tick()
        // maxAge(days: 0) → the cutoff is "now"; every entry above predates
        // the prune call, so all three are removed.
        let removed = try await store.prune(policy: .maxAge(days: 0))
        XCTAssertEqual(removed, 3)

        let count = try await store.count()
        XCTAssertEqual(count, 0)
    }

    func testPruneMaxAge_keepsRecentEntries() async throws {
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        for index in 0..<3 {
            try await store.insert(text: "entry \(index)", sourceApp: nil)
        }
        // A 30-day window keeps everything just inserted.
        let removed = try await store.prune(policy: .maxAge(days: 30))
        XCTAssertEqual(removed, 0)

        let count = try await store.count()
        XCTAssertEqual(count, 3)
    }

    // MARK: - Search

    func testSearch_findsByWordAndPrefix() async throws {
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        try await store.insert(text: "the quick brown fox", sourceApp: nil)
        try await tick()
        try await store.insert(text: "a lazy sleeping dog", sourceApp: nil)

        let byWord = try await store.search("quick")
        XCTAssertEqual(byWord.map(\.text), ["the quick brown fox"])

        let byOtherWord = try await store.search("dog")
        XCTAssertEqual(byOtherWord.map(\.text), ["a lazy sleeping dog"])

        // Prefix match — the query builder appends `*` to each token.
        let byPrefix = try await store.search("slee")
        XCTAssertEqual(byPrefix.map(\.text), ["a lazy sleeping dog"])
    }

    func testSearch_emptyQueryFallsBackToRecent() async throws {
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        try await store.insert(text: "only entry", sourceApp: nil)
        let results = try await store.search("   ")
        XCTAssertEqual(results.map(\.text), ["only entry"])
    }

    func testSearch_noMatchReturnsEmpty() async throws {
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        try await store.insert(text: "hello world", sourceApp: nil)
        let results = try await store.search("zzzznomatch")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearch_toleratesPunctuationInQuery() async throws {
        // The query builder double-quotes each token, so punctuation in the
        // user's input can't break FTS5's MATCH grammar.
        let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        try await store.insert(text: "ship it now", sourceApp: nil)
        let results = try await store.search("ship (it)!")
        XCTAssertEqual(results.map(\.text), ["ship it now"])
    }

    // MARK: - Encryption at rest

    func testVaultFileIsEncrypted_notPlaintext() async throws {
        let needle = "NEEDLE-\(UUID().uuidString)"
        do {
            let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
            try await store.insert(text: needle, sourceApp: "SecretApp")
        }
        // The store is released and its SQLite connection closed; the file
        // on disk now holds only encrypted pages.
        let raw = try Data(contentsOf: vaultURL)
        XCTAssertFalse(raw.isEmpty)

        // A SQLCipher-encrypted database does NOT begin with SQLite's
        // plaintext "SQLite format 3\0" magic — the header is encrypted too.
        // If this fails, SQLITE_HAS_CODEC=1 is missing and the vault is
        // being written in the clear.
        let magic = Data("SQLite format 3\u{0}".utf8)
        XCTAssertNotEqual(raw.prefix(magic.count), magic,
                          "vault file starts with the plaintext SQLite header")

        // The transcript text must not appear in cleartext anywhere.
        XCTAssertNil(raw.range(of: Data(needle.utf8)),
                     "transcript text found in cleartext in the vault file")

        // Sanity: with the right key the entry is still readable.
        let reopened = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonicA)
        let recovered = try await reopened.recent()
        XCTAssertEqual(recovered.first?.text, needle)
    }
}

/// Coverage for `HistoryVaultKey` — the mnemonic → raw SQLCipher key
/// derivation that backs the vault's encryption.
final class HistoryVaultKeyTests: XCTestCase {

    private let mnemonicA = "abandon abandon abandon abandon abandon abandon "
        + "abandon abandon abandon abandon abandon about"
    private let mnemonicB = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong"

    func testRawKey_is256Bits() {
        XCTAssertEqual(HistoryVaultKey.rawKey(forMnemonic: mnemonicA).bitCount, 256)
    }

    func testPragmaValue_isRawKeyBlobLiteral() {
        let pragma = HistoryVaultKey.sqlcipherKeyPragmaValue(forMnemonic: mnemonicA)
        // SQLCipher raw-key form: x'<64 lowercase hex chars>'.
        XCTAssertTrue(pragma.hasPrefix("x'"))
        XCTAssertTrue(pragma.hasSuffix("'"))
        let hex = pragma.dropFirst(2).dropLast()
        XCTAssertEqual(hex.count, 64)
        XCTAssertTrue(hex.allSatisfy(\.isHexDigit))
        XCTAssertEqual(String(hex), String(hex).lowercased())
    }

    func testPragmaValue_isDeterministic() {
        XCTAssertEqual(
            HistoryVaultKey.sqlcipherKeyPragmaValue(forMnemonic: mnemonicA),
            HistoryVaultKey.sqlcipherKeyPragmaValue(forMnemonic: mnemonicA)
        )
    }

    func testPragmaValue_differsPerMnemonic() {
        XCTAssertNotEqual(
            HistoryVaultKey.sqlcipherKeyPragmaValue(forMnemonic: mnemonicA),
            HistoryVaultKey.sqlcipherKeyPragmaValue(forMnemonic: mnemonicB)
        )
    }
}
