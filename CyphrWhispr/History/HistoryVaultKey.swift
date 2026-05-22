import Foundation
import CryptoKit
import Security

/// Key management for the encrypted history vault.
///
/// Two pieces, both isolated here per the project rule that crypto code stays
/// in one well-commented place:
///
///   • `HistoryVaultKey` — pure derivation. mnemonic → BIP-39 seed → 256-bit
///     raw SQLCipher key, via HKDF-SHA256 bound to an app-specific context.
///   • `HistoryKeychain` — persists the mnemonic in the macOS login Keychain
///     so the vault unlocks automatically on every launch. The phrase never
///     touches a plain file; macOS encrypts the Keychain at rest and unlocks
///     it with the user's login.
///
/// The mnemonic is the single source of truth: stored once, it both unlocks
/// the vault and is what we show back to the user as their recovery phrase.

// MARK: - Key derivation

enum HistoryVaultKey {

    /// HKDF `info` string. It namespaces this derivation so the same BIP-39
    /// seed could safely feed other key derivations in future. The `v1`
    /// suffix is a guard: changing the derivation would orphan every existing
    /// vault, so bump it only with a migration plan.
    private static let derivationInfo = "CyphrWhispr.HistoryVault.v1"

    /// Derive the raw 256-bit key SQLCipher uses to encrypt the vault.
    ///
    /// mnemonic → 64-byte BIP-39 seed → HKDF-SHA256 → 32-byte key. HKDF rather
    /// than truncating the seed: it folds all 512 input bits into the 256-bit
    /// output and binds the result to a CyphrWhispr-specific context.
    static func rawKey(forMnemonic mnemonic: String) -> SymmetricKey {
        let seed = BIP39.seed(from: mnemonic)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: seed),
            info: Data(derivationInfo.utf8),
            outputByteCount: 32
        )
    }

    /// The exact string to hand SQLCipher's `PRAGMA key`. The `x'…'` blob form
    /// tells SQLCipher to use the bytes *directly* as the key — skipping its
    /// own passphrase KDF, since BIP-39 + HKDF already did that work. SQLCipher
    /// still generates and header-stores a random per-database salt.
    static func sqlcipherKeyPragmaValue(forMnemonic mnemonic: String) -> String {
        let hex = rawKey(forMnemonic: mnemonic)
            .withUnsafeBytes { buffer in buffer.map { String(format: "%02x", $0) }.joined() }
        return "x'\(hex)'"
    }
}

// MARK: - Keychain persistence

/// Stores the vault mnemonic in the macOS login Keychain.
///
/// We use the classic file-based login keychain (a `kSecClassGenericPassword`
/// item, no `kSecAttrSynchronizable`), not the iOS-style data-protection
/// keychain: it works reliably for a non-sandboxed, self-signed menu-bar app,
/// auto-unlocks with the user's login session, is ACL-scoped to this app, and
/// — because `kSecAttrSynchronizable` is never set — never leaves the device
/// via iCloud Keychain. (Opt-in iCloud sync is a deferred v1.1 item.)
enum HistoryKeychain {

    private static let service = "com.cyphr.whispr.history"
    private static let account = "vault-mnemonic"

    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    /// Store (or replace) the vault mnemonic.
    static func storeMnemonic(_ mnemonic: String) throws {
        // Delete any existing item first — there is only ever one vault
        // mnemonic, so this is simpler than SecItemUpdate's attribute merge.
        SecItemDelete(baseQuery() as CFDictionary)

        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(mnemonic.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// The stored mnemonic, or `nil` if the vault has never been set up.
    static func loadMnemonic() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// True if a vault mnemonic is stored — i.e. history has been set up.
    static var hasMnemonic: Bool { loadMnemonic() != nil }

    /// Erase the mnemonic. After this the encrypted vault file is permanently
    /// unrecoverable, so callers delete the file in the same breath.
    static func deleteMnemonic() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
