import Foundation
import CryptoKit
import CommonCrypto
import Security

/// BIP-39 mnemonic generation, validation, and seed derivation.
///
/// CyphrWhispr uses BIP-39 for exactly one job: deriving the key that encrypts
/// the transcription-history vault. The 12-word mnemonic is the user's
/// *recovery phrase* — written down once, it can re-open the vault on a fresh
/// install or a second Mac. Day to day the derived key lives in the login
/// Keychain (see `HistoryVaultKey`); the phrase is the backup path, nothing
/// more, and is never persisted by the app itself.
///
/// This is a deliberately small, self-contained implementation with no
/// third-party crypto dependency — kept isolated here per the project rule
/// that crypto code stays isolated and well-commented. It is checked against
/// the official BIP-39 test vectors in `BIP39Tests`.
enum BIP39 {

    enum BIP39Error: Error, Equatable {
        case entropyGenerationFailed
        case invalidMnemonic
    }

    /// Word → 11-bit index lookup, built once from the canonical wordlist. A
    /// word's position in `BIP39Wordlist.words` *is* its BIP-39 code, so this
    /// is just the inverse of that array.
    private static let indexOf: [String: Int] = {
        var map = [String: Int](minimumCapacity: BIP39Wordlist.words.count)
        for (i, word) in BIP39Wordlist.words.enumerated() { map[word] = i }
        return map
    }()

    // MARK: - Generation

    /// Generate a fresh 12-word mnemonic from 128 bits of cryptographically
    /// secure entropy. 12 words is the BIP-39 minimum and what CyphrWhispr
    /// uses throughout: 128 bits is far beyond brute-force reach, and a short
    /// phrase is one users will actually write down.
    static func generateMnemonic() throws -> String {
        var entropy = Data(count: 16)
        let status = entropy.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw BIP39Error.entropyGenerationFailed }
        return entropyToMnemonic(entropy)
    }

    /// Deterministically turn raw entropy into a mnemonic. Split out from
    /// `generateMnemonic()` so the test suite can drive it with the spec's
    /// fixed-entropy vectors. `entropy` must be 16/20/24/28/32 bytes.
    static func entropyToMnemonic(_ entropy: Data) -> String {
        // Checksum = the first (entropyBits / 32) bits of SHA-256(entropy).
        let checksumBitCount = entropy.count * 8 / 32
        let hash = Data(SHA256.hash(data: entropy))

        var bits = bitArray(entropy)
        bits.append(contentsOf: bitArray(hash).prefix(checksumBitCount))

        // Each consecutive group of 11 bits selects one word.
        var words: [String] = []
        for start in stride(from: 0, to: bits.count, by: 11) {
            let index = bits[start ..< start + 11].reduce(0) { ($0 << 1) | ($1 ? 1 : 0) }
            words.append(BIP39Wordlist.words[index])
        }
        return words.joined(separator: " ")
    }

    // MARK: - Validation

    /// True if `mnemonic` is a structurally valid BIP-39 phrase: a supported
    /// word count, every word present in the list, and a matching checksum.
    static func isValid(_ mnemonic: String) -> Bool {
        (try? validate(mnemonic)) != nil
    }

    /// Validate `mnemonic` and return its normalized words, or throw
    /// `.invalidMnemonic`. Used by the "bring your own phrase" import path.
    @discardableResult
    static func validate(_ mnemonic: String) throws -> [String] {
        let words = normalizedWords(mnemonic)
        guard [12, 15, 18, 21, 24].contains(words.count) else {
            throw BIP39Error.invalidMnemonic
        }

        // Rebuild the bit string from the word indices.
        var bits: [Bool] = []
        bits.reserveCapacity(words.count * 11)
        for word in words {
            guard let index = indexOf[word] else { throw BIP39Error.invalidMnemonic }
            for shift in (0 ..< 11).reversed() {
                bits.append((index >> shift) & 1 == 1)
            }
        }

        // Split into entropy + checksum (the checksum is exactly 1/33 of the
        // total) and re-derive the checksum to confirm it matches.
        let checksumBitCount = bits.count / 33
        let entropyBitCount = bits.count - checksumBitCount
        let entropy = dataFromBits(Array(bits.prefix(entropyBitCount)))
        let expected = bitArray(Data(SHA256.hash(data: entropy))).prefix(checksumBitCount)
        guard Array(bits.suffix(checksumBitCount)) == Array(expected) else {
            throw BIP39Error.invalidMnemonic
        }
        return words
    }

    // MARK: - Seed derivation

    /// Derive the 64-byte BIP-39 seed from a mnemonic via PBKDF2-HMAC-SHA512
    /// (2048 iterations, salt `"mnemonic"` + passphrase) — exactly the BIP-39
    /// spec. `passphrase` is the standard optional "25th word"; CyphrWhispr
    /// leaves it empty. `HistoryVaultKey` is what consumes this seed.
    static func seed(from mnemonic: String, passphrase: String = "") -> Data {
        // The spec mandates NFKD normalization of both inputs before hashing.
        let password = Array(mnemonic.decomposedStringWithCompatibilityMapping.utf8)
        let salt = Array(("mnemonic" + passphrase).decomposedStringWithCompatibilityMapping.utf8)

        // CommonCrypto's `password` parameter is `const char *` (signed); the
        // bit pattern is what matters, so reinterpret the UTF-8 bytes as Int8.
        let passwordSigned = password.map { Int8(bitPattern: $0) }

        var derived = Data(count: 64)
        let result = derived.withUnsafeMutableBytes { out -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordSigned, passwordSigned.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                2048,
                out.baseAddress!.assumingMemoryBound(to: UInt8.self), 64
            )
        }
        precondition(result == Int32(kCCSuccess), "PBKDF2-HMAC-SHA512 derivation failed")
        return derived
    }

    // MARK: - Bit helpers

    /// Flatten bytes into MSB-first bits.
    private static func bitArray(_ data: Data) -> [Bool] {
        var bits: [Bool] = []
        bits.reserveCapacity(data.count * 8)
        for byte in data {
            for shift in (0 ..< 8).reversed() {
                bits.append((byte >> shift) & 1 == 1)
            }
        }
        return bits
    }

    /// Pack MSB-first bits back into bytes. `bits.count` must be a multiple of 8.
    private static func dataFromBits(_ bits: [Bool]) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(bits.count / 8)
        for start in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for offset in 0 ..< 8 { byte = (byte << 1) | (bits[start + offset] ? 1 : 0) }
            bytes.append(byte)
        }
        return Data(bytes)
    }

    /// Lowercase, whitespace-collapsed words. BIP-39 phrases are space-joined;
    /// we also tolerate stray newlines/tabs from copy-paste.
    private static func normalizedWords(_ mnemonic: String) -> [String] {
        mnemonic
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
            .map(String.init)
    }
}
