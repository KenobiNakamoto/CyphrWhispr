import SwiftUI

/// Root of the Settings window. Custom-built shell so we can apply the dark
/// gradient backdrop, our own segmented tab control with the violet glow on
/// the active tab, and consistent spacing across the three tabs.
struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case shortcut = "Shortcut"
        case models   = "Models"
        case about    = "About"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .shortcut
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        ZStack {
            // Vertical dark gradient — same palette as the pill window so
            // they read as part of one app.
            SettingsDesign.windowBackground
                .ignoresSafeArea()

            VStack(spacing: 18) {
                // Custom segmented tabs.
                SegmentedTabs(selection: $tab)
                    .padding(.top, 12)
                    .environmentObject(prefs)

                // Active tab content.
                Group {
                    switch tab {
                    case .shortcut: ShortcutTabView()
                    case .models:   ModelsTabView()
                    case .about:    AboutTabView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        // Min size keeps the layout from collapsing; no max so the user can
        // resize the window freely. The NSWindow itself enforces an even tighter
        // floor via `minSize` in SettingsWindowController.
        .frame(minWidth: 460, idealWidth: 520, maxWidth: .infinity,
               minHeight: 540, idealHeight: 640, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Segmented tab control

/// Capsule-segmented control inspired by macOS Settings but restyled to match
/// the design: muted-white text on inactive segments, soft violet pill behind
/// the selected one with a thin violet outline. Animates the pill across with
/// `matchedGeometryEffect` so the swap feels native.
private struct SegmentedTabs: View {
    @Binding var selection: SettingsView.Tab
    @Namespace private var ns
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SettingsView.Tab.allCases) { tab in
                let isActive = (tab == selection)
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        selection = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(SettingsDesign.krButton(size: 13, active: isActive))
                        .foregroundStyle(isActive
                                         ? SettingsDesign.textPrimary
                                         : SettingsDesign.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            ZStack {
                                if isActive {
                                    Capsule()
                                        .fill(prefs.activeTabFill)
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(prefs.accent.opacity(0.55),
                                                              lineWidth: 1)
                                        )
                                        // Soft outer glow — sells "active".
                                        .shadow(color: prefs.accent.opacity(0.45),
                                                radius: 8, x: 0, y: 0)
                                        .matchedGeometryEffect(id: "tabPill", in: ns)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
                )
        )
    }
}
