import SwiftUI

/// Settings → Polish tab. The user-facing surface for the "clean up my
/// dictation with Apple's on-device language model" feature.
///
/// Layout, top to bottom:
///
///   1. Hero card — icon + title + one-sentence pitch + master toggle.
///   2. Availability hint — small line under the hero showing whether the
///      feature is actually reachable on this Mac. Hidden when fully OK.
///   3. Cleanup instructions card — read-only display of the active prompt
///      with a "Customise prompt" button. Once customised, the card switches
///      into edit mode with a TextEditor + "Restore default text" +
///      "Reset to default" buttons.
struct PolishTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    /// Cached cleaner result for the availability hint. Refreshed on appear
    /// (and any time the toggle moves) — checking is essentially free, so
    /// we don't bother debouncing.
    @State private var availability: PolishAvailability = .disabledInSettings

    /// The cleaner used purely for availability probing here. The real
    /// pipeline cleaner lives on AppCoordinator; this one is a separate
    /// instance so the tab doesn't need a reference to AppCoordinator.
    /// `FoundationModelsCleaner` is stateless, so two instances cost nothing.
    private let prober: TranscriptionCleaner = FoundationModelsCleaner()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .padding(.bottom, 4)
        }
        .task(id: prefs.polishEnabled) { await refreshAvailability() }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 14) {
            heroCard
            if shouldShowAvailabilityHint {
                availabilityHint
            }
            promptCard
        }
    }

    // MARK: - Hero (toggle)

    private var heroCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 12) {
                SettingsIconBadge(systemName: "wand.and.stars")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Polish")
                        .font(SettingsDesign.krTitle(size: 17))
                        .foregroundStyle(SettingsDesign.textPrimary)
                    Text("Cleans up filler words, fixes punctuation, preserves your meaning. Runs on-device.")
                        .font(SettingsDesign.krBody(size: 12))
                        .foregroundStyle(SettingsDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $prefs.polishEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(prefs.accent)
            }
        }
    }

    // MARK: - Availability hint

    /// Only shown when there's something useful to tell the user. Suppressed
    /// when the cleaner is fully `.available` AND the toggle is on — at that
    /// point silence reads as "everything is fine" better than restating it.
    private var shouldShowAvailabilityHint: Bool {
        if availability == .available && prefs.polishEnabled { return false }
        return true
    }

    private var availabilityHint: some View {
        HStack(spacing: 10) {
            Image(systemName: hintIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hintTint)
            Text(displayedAvailability.explainer)
                .font(SettingsDesign.krCaption(size: 11))
                .foregroundStyle(SettingsDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsDesign.cardStroke, lineWidth: 1)
                )
        )
    }

    /// Show "polish is just turned off in settings" if the toggle is off,
    /// even when the OS would otherwise be available — that's the more
    /// actionable thing for the user to read.
    private var displayedAvailability: PolishAvailability {
        if !prefs.polishEnabled { return .disabledInSettings }
        return availability
    }

    private var hintIcon: String {
        switch displayedAvailability {
        case .available:                   return "checkmark.circle.fill"
        case .disabledInSettings:          return "circle.dotted"
        case .modelDownloading:            return "arrow.down.circle"
        case .requiresMacOS26,
             .appleIntelligenceDisabled,
             .deviceIneligible:
            return "exclamationmark.circle"
        }
    }

    private var hintTint: Color {
        switch displayedAvailability {
        case .available:           return prefs.accent
        case .disabledInSettings:  return SettingsDesign.textTertiary
        default:                   return SettingsDesign.textSecondary
        }
    }

    // MARK: - Prompt card

    private var promptCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("Cleanup instructions")
                        .font(SettingsDesign.krBody(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsDesign.textPrimary)
                    Spacer()
                    Text(prefs.polishPromptIsCustomised ? "CUSTOMISED" : "DEFAULT")
                        .font(SettingsDesign.krCaption(size: 9, weight: .bold))
                        .foregroundStyle(prefs.polishPromptIsCustomised
                                         ? prefs.accent
                                         : SettingsDesign.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.white.opacity(0.06))
                        )
                }

                if prefs.polishPromptIsCustomised {
                    customisedPromptEditor
                } else {
                    defaultPromptDisplay
                }

                promptControls
            }
        }
        .opacity(prefs.polishEnabled ? 1.0 : 0.55)
        .animation(.easeInOut(duration: 0.18), value: prefs.polishEnabled)
    }

    // MARK: - Prompt — default (read-only)

    private var defaultPromptDisplay: some View {
        // ScrollView so a longer default doesn't blow up the tab height.
        // 8-line cap keeps the layout predictable on small windows.
        ScrollView(.vertical, showsIndicators: true) {
            Text(CleanupPrompt.defaultPrompt)
                .font(SettingsDesign.krBody(size: 12))
                .foregroundStyle(SettingsDesign.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .textSelection(.enabled)
        }
        .frame(minHeight: 140, maxHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsDesign.cardStroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Prompt — customised (editable)

    private var customisedPromptEditor: some View {
        // SwiftUI TextEditor doesn't expose a clean way to apply a custom
        // background, so we layer it inside the same rounded rectangle the
        // read-only display uses. Krypton via .font() — TextEditor respects it.
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(prefs.accent.opacity(0.40), lineWidth: 1)
                )

            TextEditor(text: $prefs.polishCustomPrompt)
                .font(SettingsDesign.krBody(size: 12))
                .foregroundStyle(SettingsDesign.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .frame(minHeight: 180, maxHeight: 280)
    }

    // MARK: - Prompt controls

    @ViewBuilder
    private var promptControls: some View {
        HStack(spacing: 10) {
            if prefs.polishPromptIsCustomised {
                Button("Restore default text") {
                    prefs.polishCustomPrompt = CleanupPrompt.defaultPrompt
                }
                .buttonStyle(GhostButtonStyle())
                .help("Replace your edits with the original default prompt — but stay in customised mode so you can re-edit.")

                Button("Reset to default") {
                    prefs.resetPolishPrompt()
                }
                .buttonStyle(GhostButtonStyle())
                .help("Switch back to the read-only default. Your last edits are kept and restored if you re-customise.")

                Spacer()
            } else {
                Spacer()
                Button("Customise prompt") {
                    prefs.enablePolishCustomPrompt()
                }
                .buttonStyle(GhostButtonStyle())
                .help("Edit the cleanup instructions. The default text is copied in so you can tweak it instead of starting from scratch.")
            }
        }
    }

    // MARK: - Helpers

    private func refreshAvailability() async {
        let probed = await prober.availability()
        await MainActor.run {
            self.availability = probed
        }
    }
}

#Preview("Default — toggle off") {
    let prefs = PreferencesStore.shared
    prefs.polishEnabled = false
    prefs.polishPromptIsCustomised = false
    return PolishTabView()
        .environmentObject(prefs)
        .frame(width: 520, height: 700)
        .background(SettingsDesign.windowBackground)
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
        .frame(width: 520, height: 700)
        .background(SettingsDesign.windowBackground)
        .preferredColorScheme(.dark)
}
