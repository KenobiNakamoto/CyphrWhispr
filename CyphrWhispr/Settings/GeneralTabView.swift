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
            DropdownButton(
                currentLabel: prefs.activationMode.displayName,
                options: PreferencesStore.ActivationMode.allCases.map { mode in
                    DropdownOption(
                        label: mode.displayName,
                        isSelected: prefs.activationMode == mode
                    ) {
                        prefs.activationMode = mode
                    }
                }
            )
        }
    }

    private var dictationLanguageRow: some View {
        CardRow(
            title: "Dictation language",
            description: dictationLanguageHint
        ) {
            DropdownButton(
                currentLabel: currentLanguageDisplay,
                options: languageDropdownOptions,
                enabled: prefs.activeModelSupportsLanguageChoice
            )
        }
    }

    private var currentLanguageDisplay: String {
        switch prefs.selectedLanguageCode {
        case TranscriptionLanguageMode.autoCode:           return "Auto-detect"
        case TranscriptionLanguageMode.autoPerPhraseCode:  return "Auto — per phrase"
        default:
            return TranscriptionLanguageCatalog.language(for: prefs.selectedLanguageCode)?.displayName
                ?? prefs.selectedLanguageCode
        }
    }

    /// Catalog of options for the language pull-down. Two auto modes at the
    /// top, then the full curated language catalog in catalog order.
    private var languageDropdownOptions: [DropdownOption] {
        var opts: [DropdownOption] = []
        opts.append(
            DropdownOption(
                label: "Auto-detect — lock per session",
                isSelected: prefs.selectedLanguageCode == TranscriptionLanguageMode.autoCode
            ) {
                prefs.selectedLanguageCode = TranscriptionLanguageMode.autoCode
            }
        )
        opts.append(
            DropdownOption(
                label: "Auto-detect — per phrase (experimental)",
                isSelected: prefs.selectedLanguageCode == TranscriptionLanguageMode.autoPerPhraseCode
            ) {
                prefs.selectedLanguageCode = TranscriptionLanguageMode.autoPerPhraseCode
            }
        )
        for lang in TranscriptionLanguageCatalog.supported {
            let label = lang.nativeName.map { "\(lang.displayName) — \($0)" } ?? lang.displayName
            opts.append(
                DropdownOption(
                    label: label,
                    isSelected: prefs.selectedLanguageCode == lang.code
                ) {
                    prefs.selectedLanguageCode = lang.code
                }
            )
        }
        return opts
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
                    Button("[Customise…]") { showPolishPromptSheet = true }
                        .buttonStyle(NativeMacButtonStyle())
                        .accessibilityLabel("Customise polish prompt")
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
