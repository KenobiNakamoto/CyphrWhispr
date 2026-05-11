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

            languageCard

            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    // Header row inside the card.
                    HStack {
                        Text("Available models")
                            .font(SettingsDesign.krBody(size: 13, weight: .semibold))
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
                    .font(SettingsDesign.krCaption(size: 11))
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
                .font(SettingsDesign.krBody(size: 12.5))
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

    // MARK: - Language card
    //
    // Sits between the recommendation banner and the model list. Shows the
    // current language pick (Auto-detect by default) when the active model
    // is multilingual, or a "Switch to a multilingual model to enable"
    // hint when the active model is `.en`-only. Decoupled from the model
    // row so the user can change either independently.

    private var languageCard: some View {
        SettingsCard(padding: 14) {
            HStack(spacing: 12) {
                // Globe badge — same visual rhythm as the lightning bolt in
                // the recommendation banner, swapped for a globe to signal
                // "language" at a glance.
                Circle()
                    .fill(prefs.accentWash)
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(prefs.accent)
                    )
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictation language")
                        .font(SettingsDesign.krBody(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsDesign.textPrimary)
                    Text(languageHintText)
                        .font(SettingsDesign.krCaption(size: 11.5))
                        .foregroundStyle(SettingsDesign.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                // The picker itself. Disabled when the active model is
                // English-only — there's nothing meaningful to pick. We
                // still show the menu so the user understands the affordance
                // exists once they switch models.
                LanguagePickerMenu(
                    selectedCode: $prefs.selectedLanguageCode,
                    enabled: prefs.activeModelSupportsLanguageChoice
                )
            }
        }
    }

    /// Caption under the "Dictation language" label. Tracks the active
    /// model's English-only state + the chosen detection mode so the
    /// message reads as either instructional ("multilingual model
    /// required") or descriptive (what auto/per-phrase/pinned does).
    private var languageHintText: String {
        if !prefs.activeModelSupportsLanguageChoice {
            return "Switch to a multilingual model below to enable language selection."
        }
        switch prefs.selectedLanguageCode {
        case TranscriptionLanguageMode.autoCode:
            return "Whisper detects the language from the first second of audio, then locks it for the rest of the session."
        case TranscriptionLanguageMode.autoPerPhraseCode:
            // Be honest about the limits: phrase-level switching works at
            // natural pauses; word-level mid-utterance switching doesn't.
            return "Re-detects language after each natural pause. Code-switching between phrases works; switching within a single uninterrupted phrase will pick one language."
        default:
            let name = TranscriptionLanguageCatalog.language(for: prefs.selectedLanguageCode)?.displayName ?? prefs.selectedLanguageCode
            return "Pinned to \(name). Highest accuracy — no detection penalty."
        }
    }
}

// MARK: - Language picker menu

/// Pull-down picker of the curated language catalog. Auto-detect is sorted
/// to the top; the rest follow in catalog order (English first, then
/// alphabetical). Disabled when `enabled == false` (English-only model
/// active) but still rendered so the affordance is visible — clicking it
/// in the disabled state is a no-op.
private struct LanguagePickerMenu: View {
    @Binding var selectedCode: String
    let enabled: Bool

    var body: some View {
        Menu {
            // The two auto-detect modes pinned at the top. "Lock per
            // session" is the safer default; "Per phrase" is the polyglot
            // option (experimental — re-detects at every commit so users
            // who code-switch between phrases can get each phrase in its
            // own language).
            Button {
                selectedCode = TranscriptionLanguageMode.autoCode
            } label: {
                autoRowLabel(
                    title: "Auto-detect — lock per session",
                    isSelected: selectedCode == TranscriptionLanguageMode.autoCode
                )
            }
            Button {
                selectedCode = TranscriptionLanguageMode.autoPerPhraseCode
            } label: {
                autoRowLabel(
                    title: "Auto-detect — per phrase (experimental)",
                    isSelected: selectedCode == TranscriptionLanguageMode.autoPerPhraseCode
                )
            }

            Divider()

            // Everything else, in catalog order (English first → alphabetical).
            ForEach(TranscriptionLanguageCatalog.supported) { lang in
                Button {
                    selectedCode = lang.code
                } label: {
                    rowLabel(for: lang, isSelected: selectedCode == lang.code)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentLanguageDisplay)
                    .font(SettingsDesign.krBody(size: 12.5, weight: .medium))
                    .foregroundStyle(enabled ? SettingsDesign.textPrimary : SettingsDesign.textTertiary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(enabled ? SettingsDesign.textSecondary : SettingsDesign.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(enabled ? 0.06 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(enabled ? 0.12 : 0.06), lineWidth: 0.8)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!enabled)
        .fixedSize()
    }

    private var currentLanguageDisplay: String {
        switch selectedCode {
        case TranscriptionLanguageMode.autoCode:
            return "Auto-detect"
        case TranscriptionLanguageMode.autoPerPhraseCode:
            return "Auto — per phrase"
        default:
            return TranscriptionLanguageCatalog.language(for: selectedCode)?.displayName ?? selectedCode
        }
    }

    /// Menu row formatter for a specific language — display name + native
    /// script subtitle (when different from the English name) + checkmark
    /// on the active selection.
    @ViewBuilder
    private func rowLabel(for lang: TranscriptionLanguage, isSelected: Bool) -> some View {
        if let native = lang.nativeName {
            Text("\(lang.displayName) — \(native)")
        } else {
            Text(lang.displayName)
        }
        if isSelected {
            Image(systemName: "checkmark")
        }
    }

    /// Menu row for the auto-detect variants. Plain title text + checkmark;
    /// no native-name treatment because the row isn't a language per se,
    /// it's a detection mode.
    @ViewBuilder
    private func autoRowLabel(title: String, isSelected: Bool) -> some View {
        Text(title)
        if isSelected {
            Image(systemName: "checkmark")
        }
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
                        .font(SettingsDesign.krBody(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? prefs.accent : SettingsDesign.textPrimary)
                    if row.isCustom {
                        Text("CUSTOM")
                            .font(SettingsDesign.krCaption(size: 9, weight: .bold))
                            .foregroundStyle(SettingsDesign.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.white.opacity(0.10))
                            )
                    }
                }
                Text(row.subtitle)
                    .font(SettingsDesign.krCaption(size: 11))
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
            // Mono font means digits are already monospaced — no need for
            // .monospacedDigit() (which only applies to system fonts anyway).
            Text(formatBytes(row.diskBytes))
                .font(SettingsDesign.krCaption(size: 11, weight: .medium))
                .foregroundStyle(isActive ? prefs.accent : SettingsDesign.textSecondary)
        } else {
            Text("Not downloaded")
                .font(SettingsDesign.krCaption(size: 11))
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
