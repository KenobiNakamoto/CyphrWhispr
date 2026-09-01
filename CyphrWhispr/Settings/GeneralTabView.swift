import SwiftUI
import AppKit

/// Settings → General. Daily-driver behaviour for the dictation pill.
/// v2 glass redesign — two cards: Behaviour (launch-at-login + hide-
/// menu-bar) and Activation (mode + language + pill position).
///
/// One production-only row the v2 reference doesn't show is preserved
/// here: the dictation language dropdown (multilingual support). The
/// Polish / Apple Intelligence cleanup feature has its own sidebar tab
/// (`PolishTabView`).
struct GeneralTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead3(
                    title: "General",
                    subtitle: "Daily-driver behaviour for the dictation pill."
                )

                behaviourCard
                activationCard
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Behaviour card

    private var behaviourCard: some View {
        Card3(title: "Behaviour", meta: "2 settings") {
            Row3(label: "Launch at login",
                 sub: "Open CyphrWhispr automatically when you sign in.") {
                Toggle3(isOn: $prefs.launchAtLogin)
            }
            Row3(label: "Hide menu bar icon",
                 sub: "Run silently. Hotkey still works.",
                 isLast: true) {
                Toggle3(isOn: $prefs.hideMenuBarIcon)
            }
        }
    }

    // MARK: - Activation card

    private var activationCard: some View {
        Card3(title: "Activation", meta: "hotkey behaviour") {
            Row3(label: "Activation mode",
                 sub: "How the hotkey starts and stops a dictation session.") {
                Segmented3(
                    value: Binding(
                        get: { prefs.activationMode },
                        set: { prefs.activationMode = $0 }
                    ),
                    options: PreferencesStore.ActivationMode.allCases.map {
                        ($0, $0.displayName)
                    }
                )
            }
            Row3(label: "Dictation language",
                 sub: dictationLanguageHint) {
                languageMenu
            }
            Row3(label: "Pill position",
                 sub: "Bottom-centred. Drag to relocate; Shift-drag snaps to grid.",
                 isLast: true) {
                Text("centred · 80 pt from bottom")
                    .font(CWFont.mono(size: CWFont.s12, weight: .regular))
                    .foregroundColor(.cwFg2)
            }
        }
    }

    // MARK: - Language menu

    /// Styled SwiftUI Menu that mimics the v2 control aesthetic. Disabled
    /// (greyed out, tap-ignored) when the active model can't decode
    /// anything other than English — see PreferencesStore for the gate.
    @ViewBuilder private var languageMenu: some View {
        let enabled = prefs.activeModelSupportsLanguageChoice
        Menu {
            Button {
                prefs.selectedLanguageCode = TranscriptionLanguageMode.autoCode
            } label: {
                HStack {
                    Text("Auto-detect — lock per session")
                    if prefs.selectedLanguageCode == TranscriptionLanguageMode.autoCode {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button {
                prefs.selectedLanguageCode = TranscriptionLanguageMode.autoPerPhraseCode
            } label: {
                HStack {
                    Text("Auto-detect — per phrase (experimental)")
                    if prefs.selectedLanguageCode == TranscriptionLanguageMode.autoPerPhraseCode {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Divider()
            ForEach(TranscriptionLanguageCatalog.supported, id: \.code) { lang in
                let label = lang.nativeName.map { "\(lang.displayName) — \($0)" } ?? lang.displayName
                Button {
                    prefs.selectedLanguageCode = lang.code
                } label: {
                    HStack {
                        Text(label)
                        if prefs.selectedLanguageCode == lang.code {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentLanguageDisplay)
                    .font(CWFont.mono(size: CWFont.s12, weight: .medium))
                    .foregroundColor(enabled ? .cwFg1 : .cwFg3)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(enabled ? .cwFg2 : .cwFg3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(enabled ? 0.05 : 0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.cwBorder.opacity(enabled ? 1.0 : 0.4),
                                    lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!enabled)
        .fixedSize()
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
}

