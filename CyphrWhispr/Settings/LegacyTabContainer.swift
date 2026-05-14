import SwiftUI

// Legacy retro-terminal tab scaffolding — kept alive during the v2 glass
// migration so the not-yet-rewritten tabs (General, Shortcut, Models,
// History, About) continue to compile and render. This file gets deleted
// in the final cleanup commit once every tab is on `SectionHead3` /
// `Card3` / `Row3`.
//
// These types used to live at the bottom of `SettingsView.swift`. They
// were extracted as-is — no behaviour changes — when the shell was
// rewritten for the v2 design.

/// Shared page header used at the top of every legacy tab — page title
/// and secondary subtitle. The v2 replacement is `SectionHead3` (lives
/// in `Components/CWGlassControls.swift`).
struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SettingsDesign.krPageTitle(size: 26))
                .foregroundStyle(SettingsDesign.textPrimary)
            Text(subtitle)
                .font(SettingsDesign.krPageSubtitle(size: 12.5))
                .foregroundStyle(SettingsDesign.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared per-tab container — ScrollView + page header + content + bottom
/// spacing. The v2 replacement is a plain `VStack` with `SectionHead3` at
/// the top; the parent `SettingsView` decides whether to wrap in a
/// ScrollView. Migrated tabs drop their `SettingsTabContainer` wrapper.
struct SettingsTabContainer<Body_: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Body_

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SettingsDesign.cardSpacing) {
                SettingsPageHeader(title: title, subtitle: subtitle)
                    .padding(.bottom, SettingsDesign.pageHeaderToFirstCard
                                       - SettingsDesign.cardSpacing)
                content()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
