import SwiftUI

/// Shared design tokens for the Settings window. Colours, gradients, fonts,
/// and reusable view-modifiers all live here so the three tabs read
/// consistently and so future tweaks only have to happen in one place.
///
/// **Accent colors live on `PreferencesStore`, not here.** That's the
/// user-controlled part: the picker on the About tab writes
/// `prefs.accentHex` and every accent-using view re-reads `prefs.accent`,
/// `prefs.accentWash`, `prefs.activeTabFill`, etc. SettingsDesign owns the
/// fixed parts of the palette only — backgrounds, card surfaces, text shades.
///
/// **Typography is Monaspace Krypton** (GitHub Next, SIL OFL). The font
/// files live under `Resources/Fonts/` and are registered at app launch via
/// `ATSApplicationFontsPath` in Info.plist. Use the `kr*` helpers below
/// instead of `Font.system(...)` anywhere inside the Settings window so
/// the entire surface stays mono and on-brand. Outside Settings (the pill,
/// menu-bar items) intentionally keeps the system font.
enum SettingsDesign {
    // MARK: - Palette
    /// Window backdrop, deepest stop in the bottom-edge gradient (#050506).
    static let bgDeepest  = Color(red: 0.020, green: 0.020, blue: 0.024)
    /// Mid stop in the gradient (#0B0B0D).
    static let bgMid      = Color(red: 0.043, green: 0.043, blue: 0.051)
    /// Top stop in the gradient (#191A20).
    static let bgTop      = Color(red: 0.098, green: 0.102, blue: 0.125)

    /// Slightly raised glass-card surface (#1A1B22 @ ~92%).
    static let cardFill   = Color(red: 0.102, green: 0.106, blue: 0.133)
    /// Subtle white edge on cards (rgba(255,255,255,0.10)).
    static let cardStroke = Color.white.opacity(0.10)

    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary  = Color.white.opacity(0.42)

    // MARK: - Typography (Monaspace Krypton)
    //
    // PostScript names match the bundled .otf files under
    // `Resources/Fonts/`. SwiftUI looks up custom fonts by their
    // PostScript name, NOT the family name — `MonaspaceKrypton-Regular`
    // works; `Monaspace Krypton` would silently fall back to system mono.

    private static func krypton(weight: Font.Weight, size: CGFloat) -> Font {
        let name: String
        switch weight {
        case .medium:                  name = "MonaspaceKrypton-Medium"
        case .semibold:                name = "MonaspaceKrypton-SemiBold"
        case .bold, .heavy, .black:    name = "MonaspaceKrypton-Bold"
        default:                       name = "MonaspaceKrypton-Regular"
        }
        return .custom(name, size: size)
    }

    /// Section / tab header — large, semibold.
    static func krTitle(size: CGFloat = 22) -> Font {
        krypton(weight: .semibold, size: size)
    }
    /// Subtle subtitle under a title — secondary text colour, regular weight.
    static func krSubtitle(size: CGFloat = 13) -> Font {
        krypton(weight: .regular, size: size)
    }
    /// Default body text inside Settings.
    static func krBody(size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        krypton(weight: weight, size: size)
    }
    /// Small label-style text used in metadata rows, hints, and badges.
    static func krCaption(size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        krypton(weight: weight, size: size)
    }
    /// Buttons / segmented tab labels.
    static func krButton(size: CGFloat = 13, active: Bool = false) -> Font {
        krypton(weight: active ? .semibold : .medium, size: size)
    }

    // MARK: - Gradients

    /// Page background — vertical gradient #191A20 → #0B0B0D → #050506.
    static let windowBackground = LinearGradient(
        stops: [
            .init(color: bgTop,     location: 0.0),
            .init(color: bgMid,     location: 0.55),
            .init(color: bgDeepest, location: 1.0),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - View modifiers

/// The shared rounded glass card that wraps each tab's main content.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var padding: CGFloat = 20

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(SettingsDesign.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(SettingsDesign.cardStroke, lineWidth: 1)
            )
    }
}

/// A small rounded-square icon badge that appears next to section titles.
/// Tinted with the user's chosen accent on a low-alpha wash of the same
/// colour, matching the design screenshots.
struct SettingsIconBadge: View {
    let systemName: String
    var size: CGFloat = 32

    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(prefs.accentWash)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(prefs.accent.opacity(0.35), lineWidth: 0.8)
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(prefs.accent)
            )
    }
}
