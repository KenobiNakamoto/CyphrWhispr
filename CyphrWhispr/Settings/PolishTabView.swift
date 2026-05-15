import SwiftUI

/// Settings → Polish. The user-facing surface for the "clean up my
/// dictation with Apple's on-device language model" feature — the AI
/// layer that sits between Whisper's raw transcript and the paste at
/// the cursor (`AppCoordinator.polish(rawTranscript:)`).
///
/// v2 glass redesign. Two cards:
///   1. Apple Intelligence — master toggle + a live availability token
///      (Active / Off / Downloading / Unsupported).
///   2. Cleanup instructions — the prompt that drives the on-device
///      model. Read-only default until the user customises, then an
///      editable TextEditor with restore / reset controls.
struct PolishTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    /// Cached cleaner result for the availability token. Refreshed on
    /// appear and whenever the toggle moves — probing is essentially
    /// free, so there's nothing to debounce.
    @State private var availability: PolishAvailability = .disabledInSettings

    /// A cleaner instance used purely for availability probing here. The
    /// real pipeline cleaner lives on `AppCoordinator`; this one is
    /// separate so the tab needs no reference to the coordinator.
    /// `FoundationModelsCleaner` is stateless, so a second instance is free.
    private let prober: TranscriptionCleaner = FoundationModelsCleaner()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead3(
                    title: "Polish",
                    subtitle: "Rewrite each dictation with Apple Intelligence — on-device — "
                        + "before the text lands at your cursor. Fixes fillers, "
                        + "punctuation and capitalisation; never changes your meaning."
                )

                engineCard
                promptCard
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: prefs.polishEnabled) { await refreshAvailability() }
    }

    // MARK: - Engine card

    private var engineCard: some View {
        Card3(title: "Apple Intelligence", meta: "on-device") {
            Row3(label: "Polish transcripts",
                 sub: "Run the on-device language model over every dictation before it is typed.") {
                Toggle3(isOn: $prefs.polishEnabled)
            }
            Row3(label: "Availability",
                 sub: displayedAvailability.explainer,
                 isLast: true) {
                statusToken
            }
        }
    }

    /// Show "just turned off in settings" whenever the toggle is off,
    /// even if the OS would otherwise be available — that's the more
    /// actionable thing for the user to read.
    private var displayedAvailability: PolishAvailability {
        prefs.polishEnabled ? availability : .disabledInSettings
    }

    @ViewBuilder private var statusToken: some View {
        switch displayedAvailability {
        case .available:
            CWToken(text: "Active", variant: .active, indicator: .block)
        case .disabledInSettings:
            CWToken(text: "Off", variant: .meta)
        case .modelDownloading:
            CWToken(text: "Downloading", variant: .info)
        case .requiresMacOS26:
            CWToken(text: "macOS 26+", variant: .missing, indicator: .hollow)
        case .appleIntelligenceDisabled:
            CWToken(text: "Disabled", variant: .missing, indicator: .hollow)
        case .deviceIneligible:
            CWToken(text: "Unsupported", variant: .missing, indicator: .hollow)
        }
    }

    // MARK: - Prompt card

    private var promptCard: some View {
        Card3(title: "Cleanup instructions",
              meta: prefs.polishPromptIsCustomised ? "customised" : "default") {
            VStack(alignment: .leading, spacing: 14) {
                if prefs.polishPromptIsCustomised {
                    promptEditor
                } else {
                    promptDisplay
                }
                promptControls
            }
            .padding(16)
        }
        // Dim (but keep interactive) when polish is off — the user can
        // still prep the prompt; it just isn't doing anything yet.
        .opacity(prefs.polishEnabled ? 1.0 : 0.55)
        .animation(.easeInOut(duration: 0.18), value: prefs.polishEnabled)
    }

    /// Read-only default prompt. Capped height so a long default can't
    /// blow up the tab; scrolls internally past that.
    private var promptDisplay: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(CleanupPrompt.defaultPrompt)
                .font(CWFont.mono(size: CWFont.s12, weight: .regular))
                .foregroundColor(.cwFg2)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .textSelection(.enabled)
        }
        .frame(height: 200)
        .background(promptBox(focused: false))
    }

    /// Editable prompt. TextEditor offers no clean background hook, so it
    /// is layered inside the same rounded box the read-only display uses.
    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            promptBox(focused: true)
            TextEditor(text: $prefs.polishCustomPrompt)
                .font(CWFont.mono(size: CWFont.s12, weight: .regular))
                .foregroundColor(.cwFg1)
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .frame(height: 220)
    }

    private func promptBox(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: CWRadius.md, style: .continuous)
            .fill(Color.black.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: CWRadius.md, style: .continuous)
                    .stroke(focused ? prefs.accent.opacity(0.40) : Color.cwBorder,
                            lineWidth: 1)
            )
    }

    @ViewBuilder private var promptControls: some View {
        HStack(spacing: 8) {
            if prefs.polishPromptIsCustomised {
                CWButton(title: "Restore default text", variant: .ghost) {
                    prefs.polishCustomPrompt = CleanupPrompt.defaultPrompt
                }
                .help("Replace your edits with the original default text — but stay in customised mode so you can keep editing.")

                CWButton(title: "Reset to default", variant: .ghost) {
                    prefs.resetPolishPrompt()
                }
                .help("Switch back to the read-only default. Your edits are kept and restored if you re-customise.")

                Spacer()
            } else {
                Spacer()
                CWButton(title: "Customise prompt",
                         variant: .primary,
                         indicator: .glyph("›")) {
                    prefs.enablePolishCustomPrompt()
                }
                .help("Edit the cleanup instructions. The default text is copied in so you can tweak it instead of starting from scratch.")
            }
        }
    }

    // MARK: - Helpers

    private func refreshAvailability() async {
        let probed = await prober.availability()
        await MainActor.run { self.availability = probed }
    }
}

#Preview("Default — toggle off") {
    let prefs = PreferencesStore.shared
    prefs.polishEnabled = false
    prefs.polishPromptIsCustomised = false
    return PolishTabView()
        .environmentObject(prefs)
        .frame(width: 720, height: 720)
        .background(SettingsDesign.pageBackground)
        .preferredColorScheme(.dark)
}

#Preview("Customised — toggle on") {
    let prefs = PreferencesStore.shared
    prefs.polishEnabled = true
    prefs.polishPromptIsCustomised = true
    prefs.polishCustomPrompt = CleanupPrompt.defaultPrompt
        + "\n\nAdditional rules:\n- Always preserve technical jargon literally."
    return PolishTabView()
        .environmentObject(prefs)
        .frame(width: 720, height: 720)
        .background(SettingsDesign.pageBackground)
        .preferredColorScheme(.dark)
}
