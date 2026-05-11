import SwiftUI

/// Root of the Settings window — sidebar shell + content panel. Five fixed
/// nav items (General, Models, History, Shortcut, About) match the high-
/// fidelity mockup. The sidebar is always visible; selecting a row swaps in
/// the matching tab view on the right.
///
/// Look is intentionally retro-utility: dark slate background, monospaced
/// pixel typography (Monaspace Krypton), a hardcoded soft purple pill behind
/// the selected sidebar row with an accent-coloured left bar. Window has its
/// own custom title strip so the title text is centred (macOS doesn't centre
/// titles in `.titled` + `.fullSizeContentView` windows).
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

    /// Fixed height for our drawn title strip. Matches the standard macOS
    /// title bar height (28pt) so the centred title sits exactly in line
    /// with the traffic lights and the sidebar / content panel start
    /// immediately below — no extra empty band.
    private static let titleStripHeight: CGFloat = 28

    var body: some View {
        ZStack(alignment: .top) {
            // Background fill that runs all the way under the title strip.
            SettingsDesign.pageBackground
                .ignoresSafeArea()

            HStack(spacing: 0) {
                Sidebar(selection: $tab)
                    .frame(width: 232)
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
            .padding(.top, Self.titleStripHeight)

            // Centred title overlay sitting on top of the system title bar.
            // The bar itself is transparent (`.fullSizeContentView` +
            // `titleVisibility = .hidden`), so this is what the user sees.
            titleStrip
        }
        .frame(minWidth: 880, idealWidth: 960,  maxWidth: .infinity,
               minHeight: 600, idealHeight: 720, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    /// Custom title strip across the top of the window. Centred Monaspace
    /// title to match the mockup; the system title is hidden so the strip
    /// stands alone.
    private var titleStrip: some View {
        Text("CyphrWhispr  —  Settings")
            .font(SettingsDesign.krBody(size: 11.5, weight: .medium))
            .foregroundStyle(SettingsDesign.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: Self.titleStripHeight)
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
/// is a soft purple pill (`#241F3B` — fixed, not derived from accent) with
/// a left bar in the user's accent. Inactive rows show a gray `▸` chevron
/// before the label.
private struct Sidebar: View {
    @Binding var selection: SettingsView.Tab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "SETTINGS" header — tracked-out and dim, anchors the top of the
            // sidebar.
            Text("SETTINGS")
                .font(SettingsDesign.krSidebarHeader())
                .tracking(2.4)
                .foregroundStyle(SettingsDesign.sidebarHeader)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)

            // The five fixed nav items, in mockup order. Tight 2pt spacing
            // — the row itself supplies vertical padding for breathing room.
            VStack(spacing: 2) {
                ForEach(SettingsView.Tab.allCases) { tab in
                    SidebarRow(
                        title: tab.rawValue,
                        isActive: tab == selection,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                selection = tab
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let isActive: Bool
    let onTap: () -> Void

    @EnvironmentObject private var prefs: PreferencesStore
    @State private var isHovered = false

    /// Row content height — explicit so the active pill renders at the
    /// mockup-spec size (~36pt) instead of becoming greedy.
    private let rowHeight: CGFloat = 36

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Active state shows a filled accent dot; inactive shows a
                // small chevron. Both occupy the same 14pt slot so the
                // labels line up across rows.
                ZStack {
                    if isActive {
                        Circle()
                            .fill(prefs.accent)
                            .frame(width: 6, height: 6)
                    } else {
                        Text("▸")
                            .font(SettingsDesign.krBody(size: 11, weight: .medium))
                            .foregroundStyle(SettingsDesign.textTertiary)
                    }
                }
                .frame(width: 12, alignment: .center)

                Text(title)
                    .font(SettingsDesign.krSidebarItem(size: 13, active: isActive))
                    .foregroundStyle(isActive
                                     ? SettingsDesign.textPrimary
                                     : SettingsDesign.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Selection pill — fixed dark purple (#241F3B) per mockup spec.
            // Attached as a `.background` so it tracks the row's intrinsic
            // size rather than becoming greedy inside a ZStack.
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive
                              ? SettingsDesign.sidebarSelectionFill
                              : (isHovered
                                 ? Color.white.opacity(0.03)
                                 : Color.clear))
                    if isActive {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(prefs.accent)
                            .frame(width: 3, height: 18)
                            .padding(.leading, 1)
                    }
                }
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

/// Shared page header used at the top of every tab — page title (~22pt) and
/// secondary subtitle line. Sized + spaced to match the mockup hierarchy.
struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SettingsDesign.krPageTitle(size: 30))
                .foregroundStyle(SettingsDesign.textPrimary)
            Text(subtitle)
                .font(SettingsDesign.krPageSubtitle(size: 13))
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
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(title: title, subtitle: subtitle)
                content()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
