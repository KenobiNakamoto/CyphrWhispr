import SwiftUI

/// Root of the Settings window — sidebar shell + content panel. Five fixed
/// nav items (General, Models, History, Shortcut, About) match the high-
/// fidelity mockup. The sidebar is always visible; selecting a row swaps in
/// the matching tab view on the right.
///
/// The look is deliberately retro-utility: dark slate background, monospaced
/// pixel typography, soft purple pill behind the selected sidebar row with a
/// thin left bar in the user's accent. Inspired by Tailscale / Shottr; cards
/// and badges follow the design tokens in `SettingsDesign`.
struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general  = "General"
        case models   = "Models"
        case history  = "History"
        case shortcut = "Shortcut"
        case about    = "About"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .general
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $tab)
                .frame(width: 260)
                .frame(maxHeight: .infinity)
                .background(SettingsDesign.sidebarBackground)

            // Vertical hairline between sidebar and content.
            Rectangle()
                .fill(SettingsDesign.divider)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SettingsDesign.pageBackground)
        }
        .frame(minWidth: 880, idealWidth: 960,  maxWidth: .infinity,
               minHeight: 600, idealHeight: 720, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch tab {
            case .general:  GeneralTabView()
            case .models:   ModelsTabView()
            case .history:  HistoryTabView()
            case .shortcut: ShortcutTabView()
            case .about:    AboutTabView()
            }
        }
        .transition(.opacity)
        .id(tab) // force re-render so per-tab .onAppear refreshes fire
    }
}

// MARK: - Sidebar

/// Left-side nav. "SETTINGS" header at top, five rows beneath. Selected row
/// is a soft purple pill with a left bar in the user's accent; inactive rows
/// show a gray `▸` chevron before the label. Clicking a row swaps the tab.
private struct Sidebar: View {
    @Binding var selection: SettingsView.Tab
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "SETTINGS" header — tracked-out and dim, doubles as a visual
            // anchor at the top of the sidebar.
            Text("SETTINGS")
                .font(SettingsDesign.krSidebarHeader())
                .tracking(2.0)
                .foregroundStyle(SettingsDesign.sidebarHeader)
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 18)

            // The five fixed nav items, top-to-bottom in mockup order.
            VStack(spacing: 6) {
                ForEach(SettingsView.Tab.allCases) { tab in
                    SidebarRow(
                        title: tab.rawValue,
                        isActive: tab == selection,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selection = tab
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 14)

            Spacer()
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let isActive: Bool
    let onTap: () -> Void

    @EnvironmentObject private var prefs: PreferencesStore
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                // Selection pill — soft accent wash, only drawn when active.
                if isActive {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(prefs.accent.opacity(0.18))
                }
                HStack(spacing: 16) {
                    // Active state shows a filled accent dot; inactive shows
                    // a small chevron. Both occupy the same 14pt slot so the
                    // labels line up across rows.
                    ZStack {
                        if isActive {
                            Circle()
                                .fill(prefs.accent)
                                .frame(width: 8, height: 8)
                        } else {
                            Text("▸")
                                .font(SettingsDesign.krBody(size: 12, weight: .medium))
                                .foregroundStyle(SettingsDesign.textTertiary)
                        }
                    }
                    .frame(width: 14, alignment: .center)

                    Text(title)
                        .font(SettingsDesign.krSidebarItem(active: isActive))
                        .foregroundStyle(isActive
                                         ? SettingsDesign.textPrimary
                                         : SettingsDesign.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.vertical, 12)

                // Left accent bar that "pins" the selection. Behind the
                // label so it reads like a marker.
                if isActive {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(prefs.accent)
                            .frame(width: 3, height: 22)
                            .padding(.leading, 0)
                        Spacer()
                    }
                }
            }
            .background(
                // Hover halo on inactive rows so they feel clickable.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isActive ? 0 : (isHovered ? 0.04 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Tab content header

/// Shared page header used at the top of every tab — page title (~24pt) and
/// secondary subtitle line. Sized + spaced to match the mockup hierarchy.
struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SettingsDesign.krPageTitle())
                .foregroundStyle(SettingsDesign.textPrimary)
            Text(subtitle)
                .font(SettingsDesign.krPageSubtitle())
                .foregroundStyle(SettingsDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A shared per-tab container. Provides consistent horizontal margins, the
/// page header, and a scrollable body. Used by every tab so the layout is
/// uniform.
struct SettingsTabContainer<Body_: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Body_

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(title: title, subtitle: subtitle)
                content()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
