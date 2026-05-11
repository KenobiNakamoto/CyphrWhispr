import SwiftUI

/// Shared design tokens for the Settings window. Colours, gradients, fonts,
/// and reusable view-modifiers all live here so every tab reads consistently
/// and future tweaks only happen in one place.
///
/// **Aesthetic:** retro terminal / hacker-utility. Chunky monospaced
/// typography (Monaspace Krypton), dark slate window backdrop, bracketed
/// `[ ↓ DOWNLOADED ]`-style badges, deliberately-plain macOS-native white
/// buttons. The sidebar selection is a soft purple pill with a left bar in
/// the user's accent. Inspired by the look of native dev-utility apps
/// (Tailscale, Shottr) crossed with the Monaspace family's pixel feel.
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
    //
    // Picked off the high-fidelity mockup. Single source of truth — every
    // surface in Settings references one of these tokens rather than a raw
    // Color so a future palette tweak ripples through everything.

    /// Page background. The right-hand content panel and window backdrop
    /// both use this. Hex #0E0E11.
    static let pageBackground = Color(red: 0.055, green: 0.055, blue: 0.067)

    /// Sidebar background. Slightly raised vs the page so the vertical
    /// divider reads cleanly. Hex #181820.
    static let sidebarBackground = Color(red: 0.094, green: 0.094, blue: 0.125)

    /// Card surface — same as sidebar for visual cohesion, stroked with the
    /// divider color. Hex #181820.
    static let cardFill = Color(red: 0.094, green: 0.094, blue: 0.125)

    /// All separators: card border, row dividers, sidebar→content divider.
    /// Hex #2A2A32.
    static let divider = Color(red: 0.165, green: 0.165, blue: 0.196)

    /// Outer window border. Hex #25252C.
    static let windowStroke = Color(red: 0.145, green: 0.145, blue: 0.173)

    /// Sidebar header label colour (the "SETTINGS" caps). Hex #8A8A92.
    static let sidebarHeader = Color(red: 0.541, green: 0.541, blue: 0.573)

    /// Sidebar selection pill fill. Hardcoded from the mockup spec (#241F3B)
    /// rather than derived from the user's accent — the pill needs to read
    /// the same way regardless of which accent colour the user picks. The
    /// dot + left bar still use the accent so personal customisation has
    /// visible presence in the sidebar.
    static let sidebarSelectionFill = Color(red: 0.141, green: 0.122, blue: 0.231)
    /// Mockup-spec purple. Used for the active-row dot and left bar when
    /// the user hasn't customised their accent. Once the accent picker is
    /// touched, the runtime accent takes over.
    static let sidebarAccentDefault = Color(red: 0.490, green: 0.294, blue: 1.000)

    /// Card stroke alias kept for back-compat with `SettingsCard` callers.
    /// Same color as `divider` — both are the same #2A2A32 hairline.
    static let cardStroke = divider

    // Text shades. Three steps from white → muted, all on a dark backdrop.
    /// Hex #F3F3F4 — body text on cards, page titles.
    static let textPrimary = Color(red: 0.953, green: 0.953, blue: 0.957)
    /// Hex #A3A3AA — descriptions, subtitles.
    static let textSecondary = Color(red: 0.639, green: 0.639, blue: 0.667)
    /// Hex #77777D — metadata, dim hints.
    static let textTertiary = Color(red: 0.467, green: 0.467, blue: 0.490)

    // MARK: - Badge colours
    //
    // Bracketed-badge accents. The badge BG is a low-opacity wash of the
    // accent; the stroke + text use the saturated value. Names match the
    // mockup labels so it's obvious which token to grab.

    /// `[ ↓ DOWNLOADED ]` teal. Hex #38D2A6.
    static let badgeSuccess = Color(red: 0.220, green: 0.824, blue: 0.651)
    /// `[ □ NOT INSTALLED ]` red. Hex #FF385A.
    static let badgeDanger = Color(red: 1.000, green: 0.220, blue: 0.353)
    /// `[ * MIT ]` magenta. Hex #E24ACF.
    static let badgeMagenta = Color(red: 0.886, green: 0.290, blue: 0.812)
    /// `[ # ENCRYPTED ]` cobalt. Hex #526BFF.
    static let badgeBlue = Color(red: 0.322, green: 0.420, blue: 1.000)

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

    /// Page-level title at the top of each tab's content. Big and semibold.
    static func krPageTitle(size: CGFloat = 26) -> Font {
        krypton(weight: .semibold, size: size)
    }
    /// Page subtitle that sits directly under the title.
    static func krPageSubtitle(size: CGFloat = 13) -> Font {
        krypton(weight: .regular, size: size)
    }
    /// Card / section header — smaller than page title.
    static func krTitle(size: CGFloat = 16) -> Font {
        krypton(weight: .semibold, size: size)
    }
    /// Subtle subtitle under a title — secondary text colour, regular weight.
    static func krSubtitle(size: CGFloat = 12) -> Font {
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
    /// Bracketed badge text. Medium weight, slight letter-spacing applied
    /// at the call site via `.tracking()`.
    static func krBadge(size: CGFloat = 11) -> Font {
        krypton(weight: .medium, size: size)
    }
    /// Sidebar nav item label. Medium so it sits between body and title.
    static func krSidebarItem(size: CGFloat = 14, active: Bool = false) -> Font {
        krypton(weight: active ? .semibold : .medium, size: size)
    }
    /// SETTINGS-style uppercase section header in the sidebar. Tracked-out
    /// at the call site.
    static func krSidebarHeader(size: CGFloat = 11) -> Font {
        krypton(weight: .semibold, size: size)
    }

    // Back-compat — older code paths still ask for `krButton`. Maps to the
    // body weight scale; new code should prefer `NativeMacButtonStyle` for
    // bracketed `[Switch]`-style buttons.
    static func krButton(size: CGFloat = 13, active: Bool = false) -> Font {
        krypton(weight: active ? .semibold : .medium, size: size)
    }

    // MARK: - Window backdrop
    //
    // Solid dark slate. The mockup uses a flat fill, not a gradient — the
    // old multi-stop gradient over-softened the contrast between sidebar
    // and content panel. Exposed as a Color (which conforms to ShapeStyle
    // AND is a View) so existing `.background(SettingsDesign.windowBackground)`
    // call sites keep compiling.
    static let windowBackground: Color = pageBackground
}

// MARK: - Card

/// The shared rounded card that wraps each tab's content sections. Flat dark
/// fill + 1pt hairline border in the divider color — matches the mockup's
/// "raised slate" look without any drop shadow or blur.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var padding: CGFloat = 0
    var cornerRadius: CGFloat = 16

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(SettingsDesign.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(SettingsDesign.cardStroke, lineWidth: 1)
            )
    }
}

/// A row inside a `SettingsCard` — title + description on the left, free-form
/// trailing content (toggle, dropdown, button, badges) on the right.
/// Vertical padding matches the mockup's generous breathing room.
struct CardRow<Trailing: View>: View {
    let title: String
    let description: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SettingsDesign.krBody(size: 14, weight: .medium))
                    .foregroundStyle(SettingsDesign.textPrimary)
                if let description, !description.isEmpty {
                    Text(description)
                        .font(SettingsDesign.krCaption(size: 12))
                        .foregroundStyle(SettingsDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hairline between rows inside a card. Card has its own outer border; this
/// one only divides rows internally.
struct CardRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsDesign.divider)
            .frame(height: 1)
    }
}

// MARK: - Bracketed terminal badge

/// `[ ↓ DOWNLOADED ]`-style badge. The literal square brackets are rendered as
/// text so they sit inline with the label — that's the retro-terminal cue. A
/// thin border in the accent color wraps the whole thing.
struct TerminalBadge: View {
    let label: String
    /// Optional leading glyph rendered between the opening bracket and the
    /// label. Examples: "▪", "↓", "□", "*", "•", "#". Pass `nil` for a
    /// label-only badge like `[ ACTIVE ]`.
    var glyph: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("[")
                .font(SettingsDesign.krBadge())
                .foregroundStyle(tint)
            if let glyph {
                Text(glyph)
                    .font(SettingsDesign.krBadge())
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(SettingsDesign.krBadge())
                .foregroundStyle(tint)
                .tracking(0.5)
            Text("]")
                .font(SettingsDesign.krBadge())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(tint.opacity(0.50), lineWidth: 1)
                )
        )
    }
}

// MARK: - Native macOS button

/// Deliberately-plain white macOS-style button. Used for the action buttons in
/// each row ([Switch], [In use], [Download], [Configure…], [View on GitHub],
/// etc). The retro-terminal aesthetic everywhere else makes these buttons
/// stand out as the clickable affordances — same trick as Tailscale's macOS
/// settings.
struct NativeMacButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color(red: 0.067, green: 0.067, blue: 0.067))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed
                          ? Color(red: 0.85, green: 0.85, blue: 0.85)
                          : Color(red: 0.95, green: 0.95, blue: 0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(red: 0.72, green: 0.72, blue: 0.72),
                                          lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
    }
}

/// Ghost-style secondary button (purple text on transparent background).
/// Kept for backward compatibility with tabs that haven't migrated to the
/// native-style buttons.
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

// MARK: - Old icon badge (kept for back-compat)

/// Older icon badge used by tabs that haven't been refactored yet. New code
/// should prefer `TerminalBadge` for the bracketed-terminal aesthetic.
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
