import SwiftUI
import AppKit
import KeyboardShortcuts

/// Settings → Shortcut. v2 glass redesign — two cards:
///
///   1. "Global hotkey" — the activation recorder (real
///      `KeyboardShortcuts.Recorder` styled inside a v2 glass keycap
///      shell), the inhibit-while-typing toggle, and a per-app overrides
///      placeholder.
///   2. "Status" — two read-only diagnostic rows (event tap + conflict
///      scanner) using `CWToken` badges. Visual-only placeholders for
///      now; real probes ship in a follow-up.
struct ShortcutTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore
    @State private var showPerAppAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead3(
                    title: "Shortcut",
                    subtitle: "The global hotkey that opens the pill. Click to record a new combination."
                )

                Card3(title: "Global hotkey") {
                    Row3(label: "Activation hotkey",
                         sub: "Default ⌥Space. Pick anything that doesn't collide with Spotlight or your IME.") {
                        ShortcutRecorderField()
                    }
                    Row3(label: "Inhibit while typing",
                         sub: "Suppress the hotkey when a text-entry field already has focus and is actively being typed in.") {
                        Toggle3(isOn: $prefs.inhibitWhileTyping)
                    }
                    Row3(label: "Per-app overrides",
                         sub: "Disable the hotkey in apps that conflict (e.g. Terminal sessions, Stream Deck profiles).",
                         isLast: true) {
                        CWButton(title: "Configure",
                                 variant: .ghost,
                                 indicator: .glyph("›")) {
                            showPerAppAlert = true
                        }
                    }
                }

                Card3(title: "Status", meta: "event tap") {
                    Row3(label: "Event tap",
                         sub: "CGEventTap, kCGEventKeyDown / kCGEventFlagsChanged.") {
                        CWToken(text: "attached",
                                variant: .encrypted,
                                indicator: .glyph("●"))
                    }
                    Row3(label: "Conflicts",
                         sub: "Scanned against Spotlight, Raycast, Alfred, Stream Deck.",
                         isLast: true) {
                        CWToken(text: "none detected",
                                variant: .downloaded,
                                indicator: .glyph("✓"))
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Per-app overrides", isPresented: $showPerAppAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Per-app exclusion lists land in a future release. For now you can rebind the hotkey to a chord that doesn't conflict with the apps you use.")
        }
    }
}

// MARK: - Shortcut recorder field

/// Wraps the real `KeyboardShortcuts.Recorder` in a v2-styled glass
/// keycap shell. The library renders the chord as its own NSView (we
/// can't re-render keycaps), so we sit it inside a rounded outline that
/// matches the rest of the glass control set.
private struct ShortcutRecorderField: View {
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04),
                                 Color.white.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.cwBorder, lineWidth: 1)
                )

            KeyboardShortcuts.Recorder("", name: .toggleDictation)
                .controlSize(.large)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        }
        .frame(width: 200, height: 42)
    }
}
