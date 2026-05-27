import Foundation

/// Centralised filesystem locations for CyphrWhispr.
///
/// Models live under `~/Library/Application Support/CyphrWhispr/`, with
/// downloads ending up at `~/Library/Application Support/CyphrWhispr/models/argmaxinc/whisperkit-coreml/<variant>/`
/// because that's the layout WhisperKit's HubApi imposes given a `downloadBase`.
/// We deliberately use Application Support, not Caches: models are large,
/// expensive to re-download, and the user explicitly chose them — macOS' "purge
/// Caches" pass would feel like a regression.
enum AppSupportPaths {
    /// The repository ID we hand to WhisperKit. Kept here so the layout helpers
    /// stay in sync with what WhisperKit actually requests.
    static let whisperKitRepo = "argmaxinc/whisperkit-coreml"

    /// Lazily-resolved root: `~/Library/Application Support/CyphrWhispr/`.
    /// Created on first access; subsequent calls cheap.
    static var appSupportRoot: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let url = base.appendingPathComponent("CyphrWhispr", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// What we hand to `WhisperKitConfig.downloadBase`. WhisperKit appends
    /// `models/<repo>/<variant>` underneath this.
    static var downloadBase: URL { appSupportRoot }

    /// Concrete folder where WhisperKit will place each variant's `.mlmodelc`s.
    static var modelsRoot: URL {
        downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(whisperKitRepo, isDirectory: true)
    }

    /// Returns the on-disk URL for a specific model variant, whether or not it
    /// currently exists.
    static func modelURL(for variantID: String) -> URL {
        modelsRoot.appendingPathComponent(variantID, isDirectory: true)
    }

    /// Folder holding the encrypted history vault. Created on first access.
    /// Application Support, not Caches — the vault is user data, not a cache.
    static var historyRoot: URL {
        let url = appSupportRoot.appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The SQLCipher-encrypted transcription-history database. The file may
    /// not exist yet — `HistoryStore` creates it on first use.
    static var historyVaultURL: URL {
        historyRoot.appendingPathComponent("vault.db", isDirectory: false)
    }

    /// True if the model has been fully downloaded (folder exists and has at
    /// least one .mlmodelc subdirectory inside).
    static func isModelDownloaded(_ variantID: String) -> Bool {
        let folder = modelURL(for: variantID)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return false
        }
        return contents.contains { $0.hasSuffix(".mlmodelc") }
    }

    /// Every variant ID currently downloaded to disk. Single directory
    /// listing — cheap enough to call on every menu open without caching.
    /// Used by `ModelInventory.refresh()` (Settings → Models) and by the
    /// menu-bar status item's model switcher submenu so the two surfaces
    /// agree on what counts as installed.
    static func downloadedModelIDs() -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: modelsRoot.path) else {
            return []
        }
        return Set(names.filter { isModelDownloaded($0) })
    }

    /// Approximate disk footprint of a downloaded model (in bytes). Returns 0
    /// if the model isn't present. Used in the Models tab to show "470 MB".
    static func diskSize(of variantID: String) -> Int64 {
        let folder = modelURL(for: variantID)
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
