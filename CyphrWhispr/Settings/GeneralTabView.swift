import SwiftUI
import AppKit

/// Settings → General. Daily-driver behaviour for the dictation pill.
/// Layout matches the mockup: page title + subtitle, then a single card with
/// horizontally-divided rows. We add two rows beyond the mockup's four —
/// Dictation language (so multilingual support has a home now that it's
/// off the Models tab) and Polish (so the Apple Intelligence cleanup
/// feature stays reachable without adding a sixth sidebar item).
struct GeneralTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore
    @State private var showPolishPromptSheet = false

    var body: some View {
        SettingsTabContainer(
            title: "General",
            subtitle: "Daily-driver behaviour for the dictation pill."
        ) {
            SettingsCard {
                VStack(spacing: 0) {
                    launchAtLoginRow
                    CardRowDivider()
                    hideMenuBarRow
                    CardRowDivider()
                    activationModeRow
                    CardRowDivider()
                    dictationLanguageRow
                    CardRowDivider()
                    polishRow
                    CardRowDivider()
                    pillPositionRow
                }
            }
        }
        .sheet(isPresented: $showPolishPromptSheet) {
            PolishPromptSheet()
                .environmentObject(prefs)
        }
    }

    // MARK: - Rows

    private var launchAtLoginRow: some View {
        CardRow(
            title: "Launch at login",
            description: "Open CyphrWhispr automatically when you sign in."
        ) {
            Toggle("", isOn: $prefs.launchAtLogin)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(prefs.accent)
        }
    }

    private var hideMenuBarRow: some View {
        CardRow(
            title: "Hide menu bar icon",
            description: "Run silently. Hotkey still works."
        ) {
            Toggle("", isOn: $prefs.hideMenuBarIcon)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(prefs.accent)
        }
    }

    private var activationModeRow: some View {
        CardRow(
            title: "Activation mode",
            description: "How the hotkey starts and stops a dictation session."
        ) {
            // SwiftUI's `Menu` renders as a pull-down with the current value
            // and a chevron — visually the closest match to the mockup's
            // "Push to talk ˅" dropdown.
            Menu {
                ForEach(PreferencesStore.ActivationMode.allCases) { mode in
                    Button {
                        prefs.activationMode = mode
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            if prefs.activationMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(prefs.activationMode.displayName)
                        .font(SettingsDesign.krBody(size: 13, weight: .medium))
                        .foregroundStyle(SettingsDesign.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SettingsDesign.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(SettingsDesign.divider, lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var dictationLanguageRow: some View {
        CardRow(
            title: "Dictation language",
            description: dictationLanguageHint
        ) {
            GeneralLanguageMenu(
                selectedCode: $prefs.selectedLanguageCode,
                enabled: prefs.activeModelSupportsLanguageChoice
            )
        }
    }

    /// Caption under the language row — same logic as the old language card
    /// in Models, just adapted to fit the cleaner General-tab layout.
    private var dictationLanguageHint: String {
        if !prefs.activeModelSupportsLanguageChoice {
            return "Switch to a multilingual model on the Models tab to enable."
        }
        switch prefs.selectedLanguageCode {
        case TranscriptionLanguageMode.autoCode:
            return "Whisper detects the language from the first second of audio, then locks it."
        case TranscriptionLanguageMode.autoPerPhraseCode:
            return "Re-detects language after each natural pause. Phrase-level code-switching."
        default:
            let name = TranscriptionLanguageCatalog.language(for: prefs.selectedLanguageCode)?.displayName
                ?? prefs.selectedLanguageCode
            return "Pinned to \(name). Highest accuracy — no detection penalty."
        }
    }

    private var polishRow: some View {
        CardRow(
            title: "Polish (Apple Intelligence)",
            description: "Clean up filler words and punctuation on-device after each dictation."
        ) {
            HStack(spacing: 10) {
                if prefs.polishEnabled {
                    Button("Customise…") { showPolishPromptSheet = true }
                        .buttonStyle(NativeMacButtonStyle())
                }
                Toggle("", isOn: $prefs.polishEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(prefs.accent)
            }
        }
    }

    private var pillPositionRow: some View {
        CardRow(
            title: "Pill position",
            description: "Bottom-centred. Drag to relocate; Shift-drag snaps to grid."
        ) {
            Text("centred · 80 pt from bottom")
                .font(SettingsDesign.krCaption(size: 12))
                .foregroundStyle(SettingsDesign.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Language menu (used in General tab)

/// Pull-down picker — same data + behaviour as the legacy
/// `LanguagePickerMenu` from Models, restyled to match the General-tab
/// "row trailing control" idiom (smaller chevron treatment, fitted width).
struct GeneralLanguageMenu: View {
    @Binding var selectedCode: String
    let enabled: Bool

    var body: some View {
        Menu {
            // Two auto-detect modes at the top.
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

            ForEach(TranscriptionLanguageCatalog.supported) { lang in
                Button {
                    selectedCode = lang.code
                } label: {
                    rowLabel(for: lang, isSelected: selectedCode == lang.code)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentDisplay)
                    .font(SettingsDesign.krBody(size: 13, weight: .medium))
                    .foregroundStyle(enabled ? SettingsDesign.textPrimary : SettingsDesign.textTertiary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(enabled ? SettingsDesign.textSecondary : SettingsDesign.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(enabled ? 0.05 : 0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SettingsDesign.divider.opacity(enabled ? 1.0 : 0.5),
                                          lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!enabled)
        .fixedSize()
    }

    private var currentDisplay: String {
        switch selectedCode {
        case TranscriptionLanguageMode.autoCode:           return "Auto-detect"
        case TranscriptionLanguageMode.autoPerPhraseCode:  return "Auto — per phrase"
        default:
            return TranscriptionLanguageCatalog.language(for: selectedCode)?.displayName ?? selectedCode
        }
    }

    @ViewBuilder
    private func rowLabel(for lang: TranscriptionLanguage, isSelected: Bool) -> some View {
        if let native = lang.nativeName {
            Text("\(lang.displayName) — \(native)")
        } else {
            Text(lang.displayName)
        }
        if isSelected { Image(systemName: "checkmark") }
    }

    @ViewBuilder
    private func autoRowLabel(title: String, isSelected: Bool) -> some View {
        Text(title)
        if isSelected { Image(systemName: "checkmark") }
    }
}

// MARK: - Polish prompt sheet

/// Modal sheet that hosts the full Polish prompt editor. Reachable from the
/// "Customise…" button on the Polish row in General. Hosts the same
/// PolishTabView content the old sidebar tab used, just in a sheet so we
/// don't need a sixth sidebar item.
private struct PolishPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Polish — Cleanup instructions")
                    .font(SettingsDesign.krTitle(size: 16))
                    .foregroundStyle(SettingsDesign.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(NativeMacButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider().overlay(SettingsDesign.divider)

            // Inline the legacy PolishTabView for now — it has the full
            // prompt + customise affordances. Wrapped in a ScrollView so
            // long prompts fit.
            PolishTabView()
                .environmentObject(prefs)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(width: 720, height: 600)
        .background(SettingsDesign.pageBackground)
        .preferredColorScheme(.dark)
    }
}
