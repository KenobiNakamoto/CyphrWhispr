import SwiftUI
import AppKit

/// Settings → Models tab — restyled to match the high-fidelity mockup. Each
/// model row is a chunky entry with name + bracketed status badge + metadata
/// line + a native-style `[Switch]` / `[In use]` / `[Download]` action
/// button on the right. The currently-active row gets a soft accent wash to
/// match the rest of the design language.
///
/// Data layer is unchanged — `ModelInventory` still combines the curated
/// `ModelCatalog` with whatever is on disk in the models folder. The
/// language picker that used to live at the top of this tab has moved to
/// General (it's a daily-driver preference, not a model property).
struct ModelsTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore
    @StateObject private var manager = ModelInventory()

    private let profile = HardwareProfiler.profile()

    var body: some View {
        SettingsTabContainer(
            title: "Models",
            subtitle: "Apple-Silicon-accelerated Whisper variants. We picked one that fits your Mac on first launch — switch any time."
        ) {
            SettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(manager.rows.enumerated()), id: \.element.id) { index, row in
                        ModelRowView(
                            row: row,
                            recommendedID: ModelRecommender.recommend(for: profile).id,
                            isActive: prefs.activeModelID == row.id,
                            onSelect: { prefs.activeModelID = row.id },
                            onDelete: { manager.delete(row) }
                        )
                        .environmentObject(prefs)
                        if index < manager.rows.count - 1 {
                            CardRowDivider()
                        }
                    }
                }
            }

            // Footer: import button + storage path (read-only).
            HStack(spacing: 14) {
                Button("Import custom model…") { manager.importCustomModel() }
                    .buttonStyle(NativeMacButtonStyle())
                Spacer()
                Text(AppSupportPaths.modelsRoot.path.replacingOccurrences(
                    of: NSHomeDirectory(), with: "~"))
                    .font(SettingsDesign.krCaption(size: 11))
                    .foregroundStyle(SettingsDesign.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 4)
        }
        .onAppear { manager.refresh() }
    }
}

// MARK: - Model row

private struct ModelRowView: View {
    let row: ModelInventory.Row
    /// ID of the model the recommender picked for this hardware. Highlighting
    /// it as "Recommended" inside the row matches the mockup, which folds the
    /// hardware-recommendation banner into the row itself.
    let recommendedID: String
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var prefs: PreferencesStore
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                titleLine
                metadataLine
            }
            Spacer(minLength: 12)
            actionButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            isActive
                ? prefs.accent.opacity(0.10)
                : (isHovered ? Color.white.opacity(0.02) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            if row.isDownloaded && !isActive {
                Button("Remove download", role: .destructive, action: onDelete)
            }
        }
    }

    /// Row title — model display name + bracketed status badge. Two badge
    /// variants: `[ ▪ ACTIVE ]` (purple) for the currently-selected model,
    /// or the download status badge (downloaded / not installed) otherwise.
    private var titleLine: some View {
        HStack(spacing: 10) {
            Text(row.displayName)
                .font(SettingsDesign.krBody(size: 15, weight: .semibold))
                .foregroundStyle(SettingsDesign.textPrimary)

            if isActive {
                TerminalBadge(label: "ACTIVE", glyph: "▪", tint: prefs.accent)
            } else if row.isDownloaded {
                TerminalBadge(label: "DOWNLOADED",
                              glyph: "↓",
                              tint: SettingsDesign.badgeSuccess)
            } else {
                TerminalBadge(label: "NOT INSTALLED",
                              glyph: "□",
                              tint: SettingsDesign.badgeDanger)
            }

            if row.isCustom {
                TerminalBadge(label: "CUSTOM", glyph: nil, tint: SettingsDesign.badgeBlue)
            }
        }
    }

    /// One-line metadata: disk size · realtime estimate · "recommended"
    /// / "english only" / "bundled fallback" suffix.
    private var metadataLine: some View {
        Text(metadataText)
            .font(SettingsDesign.krCaption(size: 12))
            .foregroundStyle(SettingsDesign.textSecondary)
            .lineLimit(1)
    }

    private var metadataText: String {
        var parts: [String] = []
        let sizeLabel = ByteCountFormatter.string(
            fromByteCount: row.diskBytes > 0 ? row.diskBytes : Int64(row.approxSizeMB) * 1_048_576,
            countStyle: .file
        )
        parts.append(sizeLabel)
        if let speed = row.speedHint, !speed.isEmpty {
            parts.append(speed)
        }
        if row.id == recommendedID {
            parts.append("Recommended for this Mac")
        } else if Self.bundledFallbackIDs.contains(row.id) {
            parts.append("Bundled fallback")
        } else if !row.isMultilingual {
            parts.append("English-only")
        }
        return parts.joined(separator: " · ")
    }

    /// Hard-coded — these are the small `.en` variants we ship in the .app
    /// bundle so the app works offline immediately on first launch. Used
    /// only to label the metadata line; the actual loading logic lives in
    /// `WhisperKitBackend`.
    private static let bundledFallbackIDs: Set<String> = [
        "openai_whisper-small.en",
    ]

    @ViewBuilder
    private var actionButton: some View {
        if isActive {
            Button("In use") {}
                .buttonStyle(NativeMacButtonStyle())
                .disabled(true)
        } else if row.isDownloaded {
            Button("Switch") { onSelect() }
                .buttonStyle(NativeMacButtonStyle())
        } else {
            Button("Download") { onSelect() }
                .buttonStyle(NativeMacButtonStyle())
        }
    }
}

// MARK: - Inventory

/// Combines `ModelCatalog` (curated download options) with a scan of the
/// on-disk models folder (downloaded + user-imported custom models). Drives
/// the Models tab UI. Same as before — the refactor is purely cosmetic.
@MainActor
final class ModelInventory: ObservableObject {
    struct Row: Identifiable, Hashable {
        let id: String
        let displayName: String
        /// Approximate size in MB from the catalog (used when the model
        /// isn't yet downloaded so we can still show a size hint).
        let approxSizeMB: Int
        /// One-line speed description (e.g. "~1.5× realtime"). Empty for
        /// custom-imported models which have no catalog entry.
        let speedHint: String?
        let isMultilingual: Bool
        let isCustom: Bool
        let isDownloaded: Bool
        let diskBytes: Int64
    }

    @Published var rows: [Row] = []

    func refresh() {
        let downloadedIDs = scanDownloaded()
        let catalogIDs = Set(ModelCatalog.all.map(\.id))

        let catalogRows: [Row] = ModelCatalog.all.map { model in
            let downloaded = downloadedIDs.contains(model.id)
            return Row(
                id: model.id,
                displayName: model.displayName,
                approxSizeMB: model.approxSizeMB,
                speedHint: model.speedHint,
                isMultilingual: model.isMultilingual,
                isCustom: false,
                isDownloaded: downloaded,
                diskBytes: downloaded ? AppSupportPaths.diskSize(of: model.id) : 0
            )
        }

        let customRows: [Row] = downloadedIDs
            .subtracting(catalogIDs)
            .sorted()
            .map { id in
                Row(
                    id: id,
                    displayName: id,
                    approxSizeMB: 0,
                    speedHint: nil,
                    isMultilingual: true,
                    isCustom: true,
                    isDownloaded: true,
                    diskBytes: AppSupportPaths.diskSize(of: id)
                )
            }

        rows = catalogRows + customRows
    }

    private func scanDownloaded() -> Set<String> {
        let root = AppSupportPaths.modelsRoot
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        return Set(names.filter { name in
            AppSupportPaths.isModelDownloaded(name)
        })
    }

    // MARK: - Custom import

    func importCustomModel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing the model's .mlmodelc bundles"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let src = panel.url else { return }

        let name = src.lastPathComponent
        let dest = AppSupportPaths.modelURL(for: name)

        do {
            try FileManager.default.createDirectory(
                at: AppSupportPaths.modelsRoot,
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
        } catch {
            NSLog("[CyphrWhispr] Custom model import failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't import model"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        guard AppSupportPaths.isModelDownloaded(name) else {
            let alert = NSAlert()
            alert.messageText = "No .mlmodelc bundles found"
            alert.informativeText = "The chosen folder must contain at least one Core ML model bundle (e.g. AudioEncoder.mlmodelc)."
            alert.alertStyle = .warning
            alert.runModal()
            try? FileManager.default.removeItem(at: dest)
            return
        }

        refresh()
    }

    // MARK: - Delete

    func delete(_ row: Row) {
        let url = AppSupportPaths.modelURL(for: row.id)
        try? FileManager.default.removeItem(at: url)
        refresh()
    }
}
