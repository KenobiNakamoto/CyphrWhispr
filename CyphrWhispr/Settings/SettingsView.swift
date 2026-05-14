import SwiftUI

/// Root of the Settings window — v2 "liquid glass" redesign.
///
/// Layered top-to-bottom:
///   1. `LinearGradient.cwBackdrop` filling the whole window (ignores
///      the top safe area so the gradient reaches the title-bar band).
///   2. Two large blurred accent glows behind the gradient (one in the
///      user's accent, one in `cwAccentSecondary`) for a subtle ambient
///      lift — the design's signature "the room is lit by the app" feel.
///   3. A 38pt title strip with the centred `CyphrWhispr — Settings`
///      label. The AppKit traffic lights stay on the left in their
///      standard position — we leave a `Color.clear` spacer the same
///      width on the right so the centred title stays optically centred.
///   4. A horizontal split: glass sidebar on the left (220pt) with six
///      fixed tabs (General · Shortcut · Models · History · Customization
///      · About) plus a footer with version/build metadata; content panel
///      on the right that dispatches into the corresponding tab view.
///
/// The legacy retro-terminal look (chevron + pill sidebar, flat dark
/// cards, `TerminalBadge` brackets) is being replaced tab-by-tab in
/// follow-up commits. Until every tab is on `Card3` / `Row3` / `Toggle3`,
/// this shell tolerates both the new and the legacy tab bodies — each
/// tab manages its own ScrollView during the migration.
struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general       = "General"
        case shortcut      = "Shortcut"
        case models        = "Models"
        case history       = "History"
        case customization = "Customization"
        case about         = "About"

        var id: String { rawValue }

        /// One-character glyph used by the sidebar's leading chip. Picked
        /// from the design spec — terminal-y and consistent across tabs.
        var glyph: String {
            switch self {
            case .general:       return "⌘"
            case .shortcut:      return "⌥"
            case .models:        return "◇"
            case .history:       return "⌗"
            case .customization: return "◐"
            case .about:         return "∗"
            }
        }
    }

    /// Selected tab persists across launches — small UX upgrade over the
    /// previous `@State`. Storage key matches the v2 design system.
    @AppStorage("cw.settings.tab") private var selectedRaw = Tab.general.rawValue
    @EnvironmentObject private var prefs: PreferencesStore

    private var selected: Tab {
        Tab(rawValue: selectedRaw) ?? .general
    }

    /// Width reserved on each end of the titlebar HStack so the centred
    /// title text sits optically centred between the AppKit traffic
    /// lights (left) and the right window edge. ~70pt is the cluster
    /// width of the three standard window buttons including their
    /// trailing padding.
    private static let trafficLightReserve: CGFloat = 70

    /// Title-strip height in points. Matches the standard macOS title bar
    /// so the centred text sits exactly in line with the AppKit traffic
    /// lights overlay drawn by the window chrome.
    private static let titleStripHeight: CGFloat = 28

    var body: some View {
        ZStack(alignment: .top) {
            // 1. Backdrop gradient — must ignore safe area so the gradient
            //    reaches under the title bar.
            LinearGradient.cwBackdrop
                .ignoresSafeArea()

            // 2. Ambient accent glows behind the gradient. Animated implicitly
            //    via the accent reading from PreferencesStore — when the user
            //    picks a new accent, this softly retints.
            ZStack {
                Circle().fill(prefs.accent.opacity(0.10))
                    .frame(width: 700, height: 700).blur(radius: 120)
                    .offset(x: 200, y: -180)
                Circle().fill(Color.cwAccentSecondary.opacity(0.06))
                    .frame(width: 500, height: 500).blur(radius: 100)
                    .offset(x: -240, y: 220)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            // 3 + 4. Title strip + body in a VStack.
            VStack(spacing: 0) {
                titleStrip
                bodyContent
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 880, idealWidth: 960, maxWidth: .infinity,
               minHeight: 600, idealHeight: 720, maxHeight: .infinity)
    }

    // MARK: - Title strip

    /// 28pt strip at the very top of the window with `CyphrWhispr — Settings`
    /// centred in Monaspace Krypton. The AppKit traffic lights overlay this
    /// area from the window chrome; we leave a 70pt reserve on each side so
    /// the centred text doesn't collide with them.
    private var titleStrip: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.trafficLightReserve)
            Spacer()
            Text("CyphrWhispr — Settings")
                .font(CWFont.mono(size: CWFont.s12, weight: .medium))
                .foregroundColor(.cwFg2)
            Spacer()
            Color.clear.frame(width: Self.trafficLightReserve)
        }
        .frame(height: Self.titleStripHeight)
        .overlay(Rectangle().fill(Color.cwBorder).frame(height: 1), alignment: .bottom)
        // The window uses `.fullSizeContentView` so SwiftUI applies a top
        // safe-area inset matching the 28pt title bar. Without ignoring it
        // the strip lands BELOW the traffic-light row instead of overlaying
        // it. Backdrop gradient already ignores the safe area for the same
        // reason.
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Sidebar + content split

    private var bodyContent: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.cwBorder)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Sidebar(selected: Binding(
            get: { selected },
            set: { selectedRaw = $0.rawValue }
        ))
    }

    // MARK: - Content dispatcher
    //
    // Each tab view manages its own ScrollView for now — some still use the
    // legacy `SettingsTabContainer` (which wraps in a ScrollView + adds its
    // own page header), and the in-flight migration converts them one by
    // one. Once all tabs are on the v2 components we can hoist the
    // ScrollView up here.

    @ViewBuilder private var content: some View {
        Group {
            switch selected {
            case .general:       GeneralTabView()
            case .shortcut:      ShortcutTabView()
            case .models:        ModelsTabView()
            case .history:       HistoryTabView()
            case .customization: CustomizationTabView()
            case .about:         AboutTabView()
            }
        }
        .transition(.opacity)
        .id(selected)
    }
}

// MARK: - Sidebar
//
// "SETTINGS" caps header at top, six fixed nav items, then a hairline +
// version/build footer at the bottom. The whole thing sits on a soft
// translucent fill so the backdrop gradient bleeds through subtly.

private struct Sidebar: View {
    @Binding var selected: SettingsView.Tab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SETTINGS")
                .font(CWFont.mono(size: CWFont.s10, weight: .medium))
                .tracking(1.8)
                .foregroundColor(.cwFg3)
                .padding(.horizontal, 12)
                .padding(.top, 14).padding(.bottom, 10)

            ForEach(SettingsView.Tab.allCases) { tab in
                SidebarItem(tab: tab, isActive: tab == selected) {
                    withAnimation(.cwMain) { selected = tab }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("version"); Spacer(); Text(Sidebar.versionString) }
                HStack { Text("build");   Spacer(); Text(Sidebar.buildString)   }
            }
            .font(CWFont.mono(size: CWFont.s10, weight: .regular))
            .tracking(1.0)
            .foregroundColor(.cwFg3)
            .textCase(.uppercase)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .overlay(Rectangle().fill(Color.cwBorder).frame(height: 1), alignment: .top)
        }
        .frame(width: 220, alignment: .topLeading)
        .background(Color.white.opacity(0.02))
    }

    /// Pulled from Info.plist so the footer can't drift away from the
    /// actual bundle version. Reads `CFBundleShortVersionString`; falls
    /// back to "0.0.0" if missing (only happens in previews).
    static var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return "v\(v)"
    }

    static var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

private struct SidebarItem: View {
    let tab: SettingsView.Tab
    let isActive: Bool
    let action: () -> Void

    @EnvironmentObject private var prefs: PreferencesStore
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Leading glyph chip — accent fill + outer glow when active,
                // neutral white-on-dark with a 1pt hairline otherwise.
                Text(tab.glyph)
                    .font(CWFont.mono(size: CWFont.s12, weight: .semibold))
                    .foregroundColor(isActive ? .white : .cwFg2)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isActive ? prefs.accent : Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isActive ? .clear : Color.cwBorder, lineWidth: 1)
                    )
                    .shadow(color: isActive ? prefs.accent.opacity(0.45) : .clear, radius: 8)

                Text(tab.rawValue)
                    .font(CWFont.mono(size: CWFont.s13, weight: isActive ? .medium : .regular))
                    .foregroundColor(isActive ? .white : .cwFg1)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 1)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var rowBackground: some View {
        if isActive {
            LinearGradient(colors: [prefs.accent.opacity(0.18), prefs.accent.opacity(0.08)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(prefs.accent.opacity(0.35), lineWidth: 1)
                )
        } else if hovering {
            Color.white.opacity(0.04)
        } else {
            Color.clear
        }
    }
}

// MARK: - Legacy compatibility shims
//
// The legacy tab files (GeneralTabView, ModelsTabView, etc.) still call
// the old `SettingsPageHeader` and `SettingsTabContainer` helpers — both
// of which used to live at the bottom of this file. They've been moved
// to `LegacyTabContainer.swift` (created in the same Stage 3 commit) so
// this file can focus on the v2 shell. Nothing imports them from here.
