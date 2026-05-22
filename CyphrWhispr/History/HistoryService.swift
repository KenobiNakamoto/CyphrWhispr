import Foundation
import SwiftUI
import AppKit

/// The app-facing front door to the encrypted transcription history.
///
/// A `@MainActor ObservableObject` the History tab binds to directly. It owns
/// the `HistoryStore` actor, translates `PreferencesStore` retention settings
/// into a `RetentionPolicy`, and runs the enable/disable lifecycle:
///
///   • **enable**  — generate a BIP-39 phrase (first time only), store it in
///     the Keychain, open the vault.
///   • **disable** — close the vault, stop recording. The phrase and the
///     encrypted file are kept, so re-enabling later reopens the same history.
///
/// `AppCoordinator` calls `record(text:sourceApp:)` once per finished
/// dictation; everything else here drives Settings → History.
@MainActor
final class HistoryService: ObservableObject {
    static let shared = HistoryService()

    /// Entries shown in the History tab — newest first, or the filtered set
    /// while a search is active.
    @Published private(set) var entries: [HistoryRecord] = []

    /// Total stored entry count, ignoring any active search filter.
    @Published private(set) var totalCount = 0

    /// True once the vault is open and ready to record into and browse.
    @Published private(set) var isReady = false

    /// Human-readable message from the last failed vault operation, surfaced
    /// in the History tab. Nil when the last operation succeeded.
    @Published private(set) var lastError: String?

    private var store: HistoryStore?
    private let prefs = PreferencesStore.shared
    private let vaultURL = AppSupportPaths.historyVaultURL

    /// The search string currently applied, so a post-insert refresh re-runs
    /// the filter instead of clobbering it with the full recent list.
    private var activeQuery = ""

    private init() {}

    // MARK: - Lifecycle

    /// Called once at app launch. If history was left enabled in a previous
    /// session, reopen the vault, prune per policy, and load recent entries.
    func bootstrap() {
        guard prefs.historyEnabled, HistoryKeychain.hasMnemonic else { return }
        Task { await openVault() }
    }

    /// Turn history recording on. On the very first enable this generates the
    /// BIP-39 recovery phrase and returns it so the caller can show the
    /// one-time backup sheet; on a later re-enable it returns `nil` (the
    /// phrase already exists and must not be shown again unprompted).
    @discardableResult
    func enableHistory() -> String? {
        var freshPhrase: String?
        if !HistoryKeychain.hasMnemonic {
            do {
                let mnemonic = try BIP39.generateMnemonic()
                try HistoryKeychain.storeMnemonic(mnemonic)
                freshPhrase = mnemonic
            } catch {
                lastError = Self.describe(error)
                return nil
            }
        }
        prefs.historyEnabled = true
        Task { await openVault() }
        return freshPhrase
    }

    /// Stop recording and close the vault. The encrypted file and the
    /// Keychain phrase are deliberately kept — disabling is a pause, not a
    /// delete. Use `clearHistory()` to actually erase entries.
    func disableHistory() {
        prefs.historyEnabled = false
        store = nil            // dropping the last reference closes the connection
        entries = []
        totalCount = 0
        isReady = false
        activeQuery = ""
    }

    // MARK: - Recording

    /// Append a finished dictation. Fire-and-forget and best-effort: any
    /// failure is recorded in `lastError` but never propagated into the
    /// dictation/paste path. No-op when history is disabled or empty text.
    func record(text: String, sourceApp: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefs.historyEnabled, !trimmed.isEmpty, let store else { return }
        let policy = retentionPolicy
        Task {
            do {
                try await store.insert(text: text, sourceApp: sourceApp)
                _ = try await store.prune(policy: policy)
                await reload(store)
            } catch {
                lastError = Self.describe(error)
            }
        }
    }

    // MARK: - Browsing

    /// Filter the visible entries by full-text search. An empty query shows
    /// the full recent list again.
    func search(_ query: String) {
        activeQuery = query
        guard let store else { return }
        Task {
            do {
                entries = try await store.search(query)
            } catch {
                lastError = Self.describe(error)
            }
        }
    }

    /// Permanently delete every stored entry. The vault file and the recovery
    /// phrase remain, so recording can continue into an empty vault.
    func clearHistory() {
        guard let store else { return }
        activeQuery = ""   // an empty vault has nothing to keep filtered
        Task {
            do {
                try await store.clearAll()
                await reload(store)
            } catch {
                lastError = Self.describe(error)
            }
        }
    }

    /// Re-apply the current retention policy immediately. Called when the
    /// user changes a retention setting in the History tab so pruning is
    /// visible at once, rather than waiting for the next dictation.
    func applyRetentionNow() {
        guard let store else { return }
        let policy = retentionPolicy
        Task {
            do {
                _ = try await store.prune(policy: policy)
                await reload(store)
            } catch {
                lastError = Self.describe(error)
            }
        }
    }

    /// Reveal the encrypted vault file in Finder.
    func revealVaultInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([vaultURL])
    }

    /// The stored recovery phrase, for the "show my recovery phrase" affordance.
    var recoveryPhrase: String? { HistoryKeychain.loadMnemonic() }

    // MARK: - Internals

    /// Open (or create) the vault using the Keychain-stored phrase, prune it,
    /// and load the recent entries.
    ///
    /// `HistoryStore.init` does its SQLite work synchronously on this actor
    /// (the main actor). That's a deliberate, acceptable trade: opening a
    /// local SQLite file is sub-millisecond, and it keeps the open path free
    /// of detached-task plumbing.
    private func openVault() async {
        guard let mnemonic = HistoryKeychain.loadMnemonic() else {
            lastError = "No recovery phrase found — history can't be opened."
            return
        }
        do {
            let store = try HistoryStore(vaultURL: vaultURL, mnemonic: mnemonic)
            _ = try await store.prune(policy: retentionPolicy)
            self.store = store
            isReady = true
            lastError = nil
            await reload(store)
        } catch {
            lastError = Self.describe(error)
            isReady = false
        }
    }

    /// Refresh `entries` + `totalCount` from the store, honouring any active
    /// search filter so a post-insert refresh doesn't drop the user's query.
    private func reload(_ store: HistoryStore) async {
        do {
            totalCount = try await store.count()
            entries = activeQuery.isEmpty
                ? try await store.recent()
                : try await store.search(activeQuery)
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// Map the user's retention preference onto the store's policy type.
    private var retentionPolicy: RetentionPolicy {
        switch prefs.historyRetention {
        case .forever: return .keepForever
        case .days:    return .maxAge(days: prefs.historyRetentionDays)
        case .entries: return .maxEntries(prefs.historyRetentionEntryLimit)
        }
    }

    /// Turn an internal error into a sentence fit for the History tab.
    private static func describe(_ error: Error) -> String {
        switch error {
        case HistoryStoreError.wrongKey:
            return "The saved recovery phrase doesn't match this vault."
        case HistoryStoreError.openFailed(let detail):
            return "Couldn't open the history vault — \(detail)."
        case HistoryStoreError.sql(let detail):
            return "History database error — \(detail)."
        case BIP39.BIP39Error.entropyGenerationFailed:
            return "Couldn't generate a secure recovery phrase."
        default:
            return error.localizedDescription
        }
    }
}
