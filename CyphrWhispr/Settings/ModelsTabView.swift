import SwiftUI
import AppKit

/// Settings → Models. v2 glass redesign — one card listing installed +
/// remote variants from `ModelInventory`, then a "Custom models" card
/// with the import-folder action. Footer line shows the read-only models
/// directory path.
///
/// The data layer (`ModelInventory` + `HardwareProfiler` +
/// `ModelRecommender` + the `NSOpenPanel` import flow) is preserved
/// verbatim from the previous file; only the row presentation has been
/// re-skinned onto the new components.
struct ModelsTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore
    @StateObject private var manager = ModelInventory()
    /// Observe the in-flight download so we can refresh the on-disk
    /// inventory the moment a download finishes — that way a row's button
    /// transitions cleanly from "100% Downloaded" → "In use" without
    /// requiring the user to leave and re-enter the tab. Rows themselves
    /// observe the store directly for the live percentage display.
    @ObservedObject private var downloads = ModelDownloadStore.shared

    /// Toggled by the `[ EDIT ]` / `[ DONE ]` button in the Installed
    /// card's header. While true, every downloaded-but-not-active row
    /// trades its `[ › SWITCH ]` action button for a destructive
    /// `[ ✕ DELETE ]` — the only place in Settings where rows turn
    /// destructive, so we gate it behind an explicit mode flip rather
    /// than offering a permanent trash icon.
    @State private var isEditing = false

    /// The row whose delete button was just tapped — the source of the
    /// confirmation alert. `nil` when no alert is on screen. We hold the
    /// full `ModelInventory.Row` rather than just the ID so the message
    /// can show display name + disk size + footer detail without
    /// re-looking-up the row mid-deletion (the inventory refreshes after
    /// a successful delete, which would invalidate a stale ID lookup).
    @State private var rowPendingDeletion: ModelInventory.Row?

    private let profile = HardwareProfiler.profile()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead3(
                    title: "Models",
                    subtitle: "Apple-Silicon-accelerated Whisper variants. We picked one that fits your Mac on first launch — switch any time."
                )

                Card3(
                    title: "Installed",
                    meta: "\(manager.rows.count) variants",
                    content: {
                        ForEach(Array(manager.rows.enumerated()), id: \.element.id) { index, row in
                            ModelRow3(
                                row: row,
                                recommendedID: ModelRecommender.recommend(for: profile).id,
                                isActive: prefs.activeModelID == row.id,
                                isLast: index == manager.rows.count - 1,
                                isEditing: isEditing,
                                onSelect: { prefs.activeModelID = row.id },
                                onRequestDelete: { rowPendingDeletion = row }
                            )
                        }
                    },
                    headerTrailing: {
                        // The Edit/Done toggle. Renders as a small
                        // bracketed glass button matching the bracketed
                        // action buttons inside the rows — visual
                        // consistency over a system-style "Edit" link.
                        // `.ghost` variant gives a subtle translucent
                        // chip that reads as a control without
                        // competing with the row-level primary buttons.
                        CWButton(
                            title: isEditing ? "Done" : "Edit",
                            variant: isEditing ? .primary : .ghost,
                            indicator: .none
                        ) {
                            // Toggle in place. If the user closes Edit
                            // mode mid-confirmation, the alert closes
                            // too — leaving a dangling alert with no
                            // affordance back into edit mode would feel
                            // broken.
                            isEditing.toggle()
                            if !isEditing { rowPendingDeletion = nil }
                        }
                    }
                )

                Card3(title: "Custom models") {
                    Row3(label: "Import",
                         sub: "Drop any converted Core ML Whisper bundle into ~/Library/Application Support/CyphrWhispr/models/ — it shows up here marked CUSTOM.",
                         isLast: true) {
                        CWButton(title: "Import…",
                                 variant: .primary,
                                 indicator: .glyph("+")) {
                            manager.importCustomModel()
                        }
                    }
                }

                HStack(spacing: 0) {
                    Spacer()
                    Text(AppSupportPaths.modelsRoot.path.replacingOccurrences(
                        of: NSHomeDirectory(), with: "~"))
                        .font(CWFont.mono(size: CWFont.s11, weight: .regular))
                        .foregroundColor(.cwFg3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { manager.refresh() }
        // Re-scan disk the moment a download finishes (currentModelID
        // transitions back to nil). Without this, the row's cached
        // `isDownloaded` flag stays stale until the user leaves and
        // re-enters the tab — and "100% Downloaded" would then visibly
        // sit there for several extra seconds instead of becoming
        // "In use" right away.
        .onChange(of: downloads.currentModelID) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                manager.refresh()
            }
        }
        // Delete-confirmation alert. Anchored to the view root so the
        // dialog renders centred over the Settings window regardless of
        // which row triggered it — alerts attached deeper in the row
        // hierarchy can position oddly when the row scrolls off-screen
        // mid-presentation. `presenting:` carries the row data into the
        // closures so we don't have to hold a separate name/size copy.
        .alert(
            "Delete \(rowPendingDeletion?.displayName ?? "model")?",
            isPresented: Binding(
                get: { rowPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { rowPendingDeletion = nil }
                }
            ),
            presenting: rowPendingDeletion
        ) { row in
            Button("Cancel", role: .cancel) {
                rowPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                manager.delete(row)
                rowPendingDeletion = nil
            }
        } message: { row in
            let size = ByteCountFormatter.string(
                fromByteCount: row.diskBytes,
                countStyle: .file
            )
            Text("Removing \(row.displayName) frees \(size) of disk space. You can re-download it from this list at any time.")
        }
    }
}

// MARK: - Model row

/// One row inside the "Installed" card. Title + state token on the top
/// line; size · speed-hint · suffix on the metadata line. Tap anywhere
/// in the row (or the trailing action button) to make it active /
/// download / etc. — matches the existing production tap-to-switch
/// behaviour. Active row gets a left-edge accent bar and a soft accent
/// wash background.
private struct ModelRow3: View {
    let row: ModelInventory.Row
    let recommendedID: String
    let isActive: Bool
    let isLast: Bool
    /// Whether the Installed card is currently in Edit mode. When true,
    /// downloaded non-active rows swap their `[ › SWITCH ]` action button
    /// for a destructive `[ ✕ DELETE ]` that routes through `onRequestDelete`
    /// → confirmation alert → `manager.delete(...)`.
    let isEditing: Bool
    let onSelect: () -> Void
    /// Tapped on the delete button while in Edit mode. The parent uses
    /// this to populate `rowPendingDeletion`, which presents the
    /// confirmation alert. We never delete from inside the row —
    /// confirmation lives at the view-root so it doesn't get torn down
    /// by the row's own removal on disk-refresh.
    let onRequestDelete: () -> Void

    @EnvironmentObject private var prefs: PreferencesStore
    /// Observe the shared download register. When this row's variant is
    /// being fetched, swap the trailing action button from
    /// `Download`/`Switch`/`In use` to a live `XX% Downloaded` label.
    /// Other rows' buttons are unaffected because `downloads.currentModelID`
    /// is a single optional — the equality check in `actionButton` only
    /// matches the one row that's actually downloading.
    @ObservedObject private var downloads = ModelDownloadStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: CWSpace.s4) {
            VStack(alignment: .leading, spacing: 4) {
                titleLine
                metadataLine
            }
            Spacer(minLength: 14)
            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle().fill(prefs.accent).frame(width: 3)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.cwBorder).frame(height: 1)
            }
        }
        .contentShape(Rectangle())
        // Tap-to-switch only outside edit mode. Inside edit mode, taps
        // on the row body are intentionally inert — clicking should not
        // promote a model to active when the user's intent is deletion.
        // The dedicated `[ ✕ DELETE ]` button is the only affordance.
        .onTapGesture { if !isEditing { onSelect() } }
        .onHover { hovering = $0 }
        // Right-click context menu is kept as a power-user shortcut for
        // "Remove download" — same destructive action, same active-model
        // gate, just without the Edit-mode toggle ceremony. Routes
        // through the parent's confirmation alert by way of
        // `onRequestDelete`, so the right-click path benefits from the
        // same "are you sure?" guard as the Edit-mode button.
        .contextMenu {
            if row.isDownloaded && !isActive {
                Button("Remove download", role: .destructive) {
                    onRequestDelete()
                }
            }
        }
    }

    @ViewBuilder private var rowBackground: some View {
        if isActive {
            LinearGradient(colors: [prefs.accent.opacity(0.12),
                                    prefs.accent.opacity(0.04)],
                           startPoint: .top, endPoint: .bottom)
        } else if hovering {
            Color.white.opacity(0.04)
        } else {
            Color.clear
        }
    }

    /// Row title — model display name + state token + custom marker.
    /// Tokens follow v2's variant semantics: active (accent + caret),
    /// recommended (amber triangle), downloaded (mint arrow), missing
    /// (hollow), custom (violet meta chip).
    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.displayName)
                .font(CWFont.mono(size: CWFont.s13, weight: .medium))
                .foregroundColor(.cwFg1)
            stateToken
            if row.isCustom {
                CWToken(text: "custom", variant: .custom, indicator: .none)
            }
        }
    }

    @ViewBuilder private var stateToken: some View {
        if isActive {
            CWToken(text: "active",
                    variant: .active,
                    indicator: .block,
                    live: true)
        } else if !row.isDownloaded {
            CWToken(text: "not installed",
                    variant: .missing,
                    indicator: .hollow)
        } else if row.id == recommendedID {
            CWToken(text: "recommended",
                    variant: .recommended,
                    indicator: .glyph("▲"))
        } else {
            CWToken(text: "downloaded",
                    variant: .downloaded,
                    indicator: .glyph("↓"))
        }
    }

    private var metadataLine: some View {
        Text(metadataText)
            .font(CWFont.mono(size: CWFont.s11, weight: .regular))
            .foregroundColor(.cwFg3)
            .lineLimit(1)
    }

    private var metadataText: String {
        var parts: [String] = []
        let sizeLabel = ByteCountFormatter.string(
            fromByteCount: row.diskBytes > 0
                ? row.diskBytes
                : Int64(row.approxSizeMB) * 1_048_576,
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

    /// Hard-coded — these are the small `.en` variants we ship in the
    /// .app bundle so the app works offline immediately on first launch.
    private static let bundledFallbackIDs: Set<String> = [
        "openai_whisper-small.en",
    ]

    @ViewBuilder private var actionButton: some View {
        // Downloading-this-variant check wins over every other state.
        // The user clicked Download (or AppCoordinator routed a not-cached
        // model through `switchModel(...)`), so the row is mid-fetch —
        // every other label would lie about what's happening. Also wins
        // over Edit mode: a download in flight should never be replaced
        // by a delete button (it's not yet on disk to delete anyway).
        if downloads.currentModelID == row.id {
            let percent = Int((downloads.fraction * 100).rounded())
            CWButton(title: "\(percent)% Downloaded",
                     variant: .ghost) { }
        } else if isEditing && row.isDownloaded && !isActive {
            // Edit mode + this variant has bytes on disk + not the active
            // pipeline → the delete button is the only thing that makes
            // sense here. Active model stays at "In use" so the user
            // can't accidentally pull the rug out from under a running
            // dictation; non-downloaded rows just have nothing to delete.
            CWButton(title: "Delete",
                     variant: .danger,
                     indicator: .glyph("✕")) {
                onRequestDelete()
            }
        } else if isActive {
            CWButton(title: "In use", variant: .ghost) { }
        } else if !row.isDownloaded {
            CWButton(title: "Download",
                     variant: .ghost,
                     indicator: .glyph("↓")) {
                onSelect()
            }
        } else {
            CWButton(title: "Switch",
                     variant: .primary,
                     indicator: .glyph("›")) {
                onSelect()
            }
        }
    }
}

// MARK: - Inventory

/// Combines `ModelCatalog` (curated download options) with a scan of the
/// on-disk models folder (downloaded + user-imported custom models).
/// Drives the Models tab UI. Unchanged from the legacy file — the v2
/// migration is purely cosmetic.
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
        // Single source of truth lives in AppSupportPaths so the Models
        // tab and the menu-bar status item's switcher submenu agree on
        // what counts as "installed".
        AppSupportPaths.downloadedModelIDs()
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
