import SwiftUI
import KeyboardShortcuts

/// Settings → Shortcut tab, restyled to match the dark glass design.
/// The KeyboardShortcuts library's `Recorder` view does the heavy lifting of
/// capturing key chords, persisting to UserDefaults, and re-binding the global
/// hotkey — we just wrap it in a violet-glow input so it reads like the rest
/// of the design system.
struct ShortcutTabView: View {
    var body: some View {
        // ScrollView so the layout stays usable when the user resizes the
        // window below this tab's natural height.
        ScrollView(.vertical, showsIndicators: false) {
            content
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 18) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        SettingsIconBadge(systemName: "command")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dictation hotkey")
                                .font(SettingsDesign.krTitle(size: 17))
                                .foregroundStyle(SettingsDesign.textPrimary)
                            Text("Hold to dictate")
                                .font(SettingsDesign.krBody(size: 12))
                                .foregroundStyle(SettingsDesign.textSecondary)
                        }
                        Spacer()
                    }

                    // Glowing shortcut input. KeyboardShortcuts.Recorder is an
                    // NSViewRepresentable — we can't restyle its internal label,
                    // so we wrap it in our own glass capsule and let it sit on
                    // top centred. Tap the row to start recording; the library
                    // shows the placeholder/active state itself.
                    ShortcutField()

                    Text("Click the shortcut field, then press the key combination you want to use.")
                        .font(SettingsDesign.krBody(size: 12))
                        .foregroundStyle(SettingsDesign.textSecondary)
                    Text("Press any combination of ⌃ ⌥ ⌘ ⇧ plus a key.")
                        .font(SettingsDesign.krBody(size: 12))
                        .foregroundStyle(SettingsDesign.textSecondary)
                    Text("The shortcut takes effect immediately.")
                        .font(SettingsDesign.krBody(size: 12))
                        .foregroundStyle(SettingsDesign.textSecondary)

                    Divider()
                        .overlay(SettingsDesign.cardStroke)
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tips for picking a shortcut")
                            .font(SettingsDesign.krBody(size: 13, weight: .semibold))
                            .foregroundStyle(SettingsDesign.textPrimary)

                        TipRow(
                            icon: "exclamationmark.triangle.fill",
                            text: "Avoid ⌘Space (Spotlight) and ⌃⌘Space (Emoji & Symbols)."
                        )
                        TipRow(
                            icon: "hand.raised.fill",
                            text: "Hold-to-talk feels best with chords you can hold one-handed (⌥Space, ⌃Space, fn)."
                        )
                    }
                }
            }

            Spacer(minLength: 0)

            // Footer row: pill logo bottom-left, "Reset to default" bottom-right.
            HStack {
                MiniPillLogo()
                Spacer()
                Button("Reset to default") {
                    KeyboardShortcuts.reset(.toggleDictation)
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
    }
}

// MARK: - Shortcut input (glass wrapper around KeyboardShortcuts.Recorder)

private struct ShortcutField: View {
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        ZStack {
            // Glass capsule background with accent outline.
            Capsule()
                .fill(Color.black.opacity(0.35))
                .overlay(
                    Capsule()
                        .strokeBorder(prefs.accentGlowStroke, lineWidth: 1.5)
                )
                .shadow(color: prefs.accent.opacity(0.55), radius: 14, x: 0, y: 0)
                .frame(height: 52)

            // The actual recorder. We hide its label and let our background
            // provide the visual shell. Setting an empty `Text` label means
            // the recorder shows just its current key chord, centred.
            KeyboardShortcuts.Recorder("", name: .toggleDictation)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .scaleEffect(1.0)
                .padding(.horizontal, 16)
        }
    }
}

// MARK: - Tip row

private struct TipRow: View {
    let icon: String
    let text: String

    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(prefs.accentWash)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(prefs.accent)
                )
                .frame(width: 22, height: 22)
            Text(text)
                .font(SettingsDesign.krBody(size: 12))
                .foregroundStyle(SettingsDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Footer pill mark + ghost button

/// Mini version of the pill — just the triangle + circle inside a small black
/// capsule — used as a bottom-left "brand mark" in the Shortcut footer.
struct MiniPillLogo: View {
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "play.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .rotationEffect(.degrees(90))   // play.fill points right; rotate 90° → down-pointing triangle
                .frame(width: 11, height: 11)
                .foregroundStyle(.white)
            Circle()
                .fill(.white)
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.black)
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

/// Subtle button style that matches the glass aesthetic — used for the Reset
/// button and other secondary actions in the Settings UI.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsDesign.krBody(size: 12, weight: .medium))
            .foregroundStyle(SettingsDesign.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.06))
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .contentShape(Capsule())
    }
}
