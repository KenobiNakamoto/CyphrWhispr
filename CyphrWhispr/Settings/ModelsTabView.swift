import SwiftUI
import AppKit

/// Settings → Models tab, restyled to match the dark glass design (Page 2 of
/// the Settings spec). Same data model as before — `ModelInventory` combines
/// the curated `ModelCatalog` with whatever is on disk in the models folder
/// (downloads + custom imports). Selecting a row flips
/// `PreferencesStore.activeModelID`, which the AppCoordinator observes and
/// hot-reloads in the background.
struct ModelsTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore
    @StateObject private var manager = ModelInventory()

    private let profile = HardwareProfiler.profile()

    var body: some View {
        VStack(spacing: 14) {
            recommendationBanner

            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    // Header row inside the card.
                    HStack {
                        Text("Available models")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SettingsDesign.textPrimary)
                        Spacer()
                        Button("Import custom…") { manager.importCustomModel() }
                            .buttonStyle(GhostButtonStyle())
                            .help("Import a Core ML Whisper model folder (.mlmodelc bundles)")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    Divider().overlay(SettingsDesign.cardStroke)

                    // Scrollable list.
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(manager.rows) { row in
                                ModelRowView(
                                    row: row,
                                    isActive: prefs.activeModelID == row.id,
                                    onSelect: { prefs.activeModelID = row.id },
                                    onDelete: { manager.delete(row) }
                                )
                                .environmentObject(prefs)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            // Footer card with storage path + reveal button.
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsDesign.textTertiary)
                Text("Models stored at \(AppSupportPaths.modelsRoot.path)")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsDesign.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppSupportPaths.modelsRoot])
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(SettingsDesign.cardStroke, lineWidth: 1)
                    )
            )
        }
        .onAppear { manager.refresh() }
    }

    // MARK: - Banner

    private var recommendationBanner: some View {
        let recommended = ModelRecommender.recommend(for: profile)
        return HStack(spacing: 12) {
            // Accent bolt badge.
            Circle()
                .fill(prefs.accentWash)
                .overlay(
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(prefs.accent)
                )
                .frame(width: 26, height: 26)

            Text(ModelRecommender.explanation(for: profile, model: recommended))
                .font(.system(size: 12.5))
                .foregroundStyle(SettingsDesign.textSecondary)

            Spacer()

            if prefs.activeModelID != recommended.id {
                Button("Switch") {
                    prefs.activeModelID = recommended.id
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(prefs.accentWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(prefs.accent.opacity(0.30), lineWidth: 1)
                )
        )
    }
}

// MARK: - Row

private struct ModelRowView: View {
    let row: ModelInventory.Row
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Custom radio: hollow ring with accent fill when selected.
            ZStack {
                Circle()
                    .strokeBorder(isActive ? prefs.accent : Color.white.opacity(0.30),
                                  lineWidth: 1.6)
                    .frame(width: 18, height: 18)
                if isActive {
                    Circle()
                        .fill(prefs.accent)
                        .frame(width: 9, height: 9)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? prefs.accent : SettingsDesign.textPrimary)
                    if row.isCustom {
                        Text("CUSTOM")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SettingsDesign.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.white.opacity(0.10))
                            )
                    }
                }
                Text(row.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsDesign.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? prefs.accentWash : Color.clear)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            if row.isDownloaded && !isActive {
                Button("Remove download", role: .destructive, action: onDelete)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if row.isDownloaded {
            Text(formatBytes(row.diskBytes))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(isActive ? prefs.accent : SettingsDesign.textSecondary)
        } else {
            Text("Not downloaded")
                .font(.system(size: 11))
                .foregroundStyle(SettingsDesign.textTertiary)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Inventory (unchanged data layer)

/// Combines `ModelCatalog` (curated download options) with a scan of the
/// on-disk models folder (downloaded + user-imported custom models). Drives
/// the Models tab UI.
@MainActor
final class ModelInventory: ObservableObject {
    struct Row: Identifiable, Hashable {
        let id: String
        let displayName: String
        let subtitle: String
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
                subtitle: subtitle(for: model),
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
                    subtitle: "Custom Core ML model",
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

    private func subtitle(for model: WhisperModel) -> String {
        let language = model.isMultilingual ? "Multilingual" : "English-only"
        let approxSize = ByteCountFormatter.string(
            fromByteCount: Int64(model.approxSizeMB) * 1_048_576,
            countStyle: .file
        )
        return "\(language) · \(approxSize) · \(model.speedHint)"
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
