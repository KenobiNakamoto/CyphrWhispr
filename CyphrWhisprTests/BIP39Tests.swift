import XCTest
@testable import CyphrWhispr

/// Coverage for `BIP39` against the canonical (Trezor) BIP-39 English test
/// vectors, plus generation and validation behaviour.
///
/// The vectors below are the most-cited entries from the reference
/// `python-mnemonic` `vectors.json` — entropy → mnemonic → 64-byte seed, all
/// derived with the standard `"TREZOR"` passphrase. If `BIP39` disagrees with
/// any of them the implementation is wrong: these values are the spec.
final class BIP39Tests: XCTestCase {

    private struct Vector {
        let entropyHex: String
        let mnemonic: String
        let seedHex: String
    }

    private let vectors: [Vector] = [
        Vector(
            entropyHex: "00000000000000000000000000000000",
            mnemonic: "abandon abandon abandon abandon abandon abandon "
                + "abandon abandon abandon abandon abandon about",
            seedHex: "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553"
                + "1f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
        ),
        Vector(
            entropyHex: "80808080808080808080808080808080",
            mnemonic: "letter advice cage absurd amount doctor acoustic "
                + "avoid letter advice cage above",
            seedHex: "d71de856f81a8acc65e6fc851a38d4d7ec216fd0796d0a6827a3ad6ed5511a30"
                + "fa280f12eb2e47ed2ac03b5c462a0358d18d69fe4f985ec81778c1b370b652a8"
        ),
        Vector(
            entropyHex: "ffffffffffffffffffffffffffffffff",
            mnemonic: "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong",
            seedHex: "ac27495480225222079d7be181583751e86f571027b0497b5b5d11218e0a8a13"
                + "332572917f0f8e5a589620c6f15b11c61dee327651a14c34e18231052e48c069"
        ),
    ]

    // MARK: Official vectors

    func testEntropyToMnemonic_matchesOfficialVectors() {
        for vector in vectors {
            XCTAssertEqual(BIP39.entropyToMnemonic(Data(hex: vector.entropyHex)),
                           vector.mnemonic,
                           "entropy \(vector.entropyHex)")
        }
    }

    func testSeed_matchesOfficialVectors() {
        for vector in vectors {
            let seed = BIP39.seed(from: vector.mnemonic, passphrase: "TREZOR")
            XCTAssertEqual(seed.hexString, vector.seedHex,
                           "mnemonic \"\(vector.mnemonic)\"")
        }
    }

    func testVectorMnemonics_validate() throws {
        for vector in vectors {
            XCTAssertTrue(BIP39.isValid(vector.mnemonic))
            XCTAssertEqual(try BIP39.validate(vector.mnemonic).count, 12)
        }
    }

    func testEntropyToMnemonic_supports24Words() throws {
        // 256-bit entropy → 24 words. The output always carries a correct
        // checksum, so it must validate regardless of the entropy value.
        let mnemonic = BIP39.entropyToMnemonic(Data(count: 32))
        XCTAssertEqual(try BIP39.validate(mnemonic).count, 24)
    }

    // MARK: Generation

    func testGenerateMnemonic_is12ValidWords() throws {
        let mnemonic = try BIP39.generateMnemonic()
        XCTAssertEqual(try BIP39.validate(mnemonic).count, 12)
        XCTAssertTrue(BIP39.isValid(mnemonic))
    }

    func testGenerateMnemonic_isRandomEachCall() throws {
        // With 128 bits of entropy a collision is a ~2⁻¹²⁸ event — two equal
        // phrases would mean the RNG is broken.
        XCTAssertNotEqual(try BIP39.generateMnemonic(), try BIP39.generateMnemonic())
    }

    // MARK: Validation — negative cases

    func testValidate_rejectsWrongWordCount() {
        XCTAssertThrowsError(try BIP39.validate("abandon abandon abandon"))
        XCTAssertFalse(BIP39.isValid("abandon abandon abandon"))
    }

    func testValidate_rejectsUnknownWord() {
        let bad = "abandon abandon abandon abandon abandon abandon "
            + "abandon abandon abandon abandon abandon zzzznotaword"
        XCTAssertThrowsError(try BIP39.validate(bad)) { error in
            XCTAssertEqual(error as? BIP39.BIP39Error, .invalidMnemonic)
        }
    }

    func testValidate_rejectsBadChecksum() {
        // "abandon" ×12 is twelve valid words, but all-zero entropy needs
        // "about" as the 12th word — so the checksum fails.
        let bad = Array(repeating: "abandon", count: 12).joined(separator: " ")
        XCTAssertThrowsError(try BIP39.validate(bad)) { error in
            XCTAssertEqual(error as? BIP39.BIP39Error, .invalidMnemonic)
        }
    }

    func testValidate_isCaseAndWhitespaceInsensitive() throws {
        let messy = "  ABANDON  abandon abandon abandon abandon abandon "
            + "abandon abandon abandon abandon abandon ABOUT  "
        let words = try BIP39.validate(messy)
        XCTAssertEqual(words.count, 12)
        XCTAssertEqual(words.first, "abandon")
        XCTAssertEqual(words.last, "about")
    }
}

// MARK: - Test helpers

private extension Data {
    /// Build `Data` from an even-length hex string. Test-only — assumes the
    /// caller passes well-formed hex (the vectors above).
    init(hex: String) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self = Data(bytes)
    }

    /// Lowercase hex encoding, for comparing against the spec's seed strings.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
