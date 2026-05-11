import SwiftUI
import AppKit
import KeyboardShortcuts

/// Settings → Shortcut. Three-row card matching the mockup:
///
///   1. Activation hotkey — the global chord that opens the pill.
///      Rendered as the KeyboardShortcuts.Recorder wrapped in our own
///      accent-bordered shell so it reads as a retro-keycap field.
///   2. Inhibit while typing — boolean toggle, default ON. Suppresses
///      the hotkey when a text field already has focus.
///   3. Per-app overrides — placeholder button that links to a future
///      per-app exclusion UI (not implemented in v1; the button surfaces
///      a "coming soon" alert when clicked).
struct ShortcutTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore
    @State private var showPerAppAlert = false

    var body: some View {
        SettingsTabContainer(
            title: "Shortcut",
            subtitle: "The global hotkey that opens the pill. Click to record a new combination."
        ) {
            SettingsCard {
                VStack(spacing: 0) {
                    activationHotkeyRow
                    CardRowDivider()
                    inhibitWhileTypingRow
                    CardRowDivider()
                    perAppOverridesRow
                }
            }

            // Footer hint — tips that used to live in their own card. Moved
            // inline so the visible card structure matches the mockup
            // exactly (single card, three rows).
            VStack(alignment: .leading, spacing: 6) {
                Text("Press any combination of ⌃ ⌥ ⌘ ⇧ plus a key. Avoid ⌘Space (Spotlight) and ⌃⌘Space (Emoji & Symbols).")
                    .font(SettingsDesign.krCaption(size: 11))
                    .foregroundStyle(SettingsDesign.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .alert("Per-app overrides", isPresented: $showPerAppAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Per-app exclusion lists land in a future release. For now you can rebind the hotkey to a chord that doesn't conflict with the apps you use.")
        }
    }

    // MARK: - Rows

    private var activationHotkeyRow: some View {
        CardRow(
            title: "Activation hotkey",
            description: "Default ^⌘Space. Pick anything that doesn't collide with Spotlight or your IME."
        ) {
            ShortcutRecorderField()
        }
    }

    private var inhibitWhileTypingRow: some View {
        CardRow(
            title: "Inhibit while typing",
            description: "Suppress the hotkey when a text-entry field already has focus and is actively being typed in."
        ) {
            Toggle("", isOn: $prefs.inhibitWhileTyping)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(prefs.accent)
        }
    }

    private var perAppOverridesRow: some View {
        CardRow(
            title: "Per-app overrides",
            description: "Disable the hotkey in apps that conflict (e.g. Terminal sessions, Stream Deck profiles)."
        ) {
            Button("[Configure…]") {
                showPerAppAlert = true
            }
            .buttonStyle(NativeMacButtonStyle())
            .accessibilityLabel("Configure per-app overrides")
        }
    }
}

// MARK: - Shortcut recorder field

/// Wraps the `KeyboardShortcuts.Recorder` in our own accent-bordered shell.
/// The library renders the active key chord as its own NSView (we can't
/// re-render those keycaps), so we sit it inside a rounded outline + soft
/// accent glow that visually matches the mockup's three-keycap field. The
/// glow tints with the user's chosen accent so the recorder remains the
/// most accent-tinted control on the Shortcut tab.
private struct ShortcutRecorderField: View {
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(prefs.accent.opacity(0.55), lineWidth: 1.3)
                )
                .shadow(color: prefs.accent.opacity(0.32), radius: 8, x: 0, y: 0)

            KeyboardShortcuts.Recorder("", name: .toggleDictation)
                .controlSize(.large)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .frame(width: 200, height: 42)
    }
}
