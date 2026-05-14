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

    // MARK: - Spacing scale
    //
    // 8pt grid throughout — every spacing decision in Settings derives from
    // one of these constants. Keeps the visual rhythm consistent across tabs
    // and makes future polish a single-constant edit.

    /// Gap between cards in a tab. Mockup rhythm.
    static let cardSpacing: CGFloat = 16
    /// Gap between the page header and the first card.
    static let pageHeaderToFirstCard: CGFloat = 22
    /// Horizontal padding inside a card row.
    static let rowPaddingHorizontal: CGFloat = 22
    /// Vertical padding inside a card row.
    static let rowPaddingVertical: CGFloat = 18
    /// Outer card corner radius.
    static let cardCornerRadius: CGFloat = 12
    /// Outer card border width.
    static let cardBorderWidth: CGFloat = 1

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

// MARK: - v2 glass design tokens
//
// New token namespace introduced with the `v2 glass` redesign. Mirrors the
// Claude-Design `colors_and_type.css` source-of-truth 1:1. Lives alongside
// the legacy `SettingsDesign` tokens above so the migration can land in
// stages — once every tab is on `cw*` / `Card3` / `Row3`, the legacy block
// above is safe to delete.
//
// Reference: `/Visual Aides/Setting Menu/Reference Design Files`.

extension Color {
    // Backdrop gradient stops
    static let cwBgDeepest = Color(red: 0.020, green: 0.020, blue: 0.024)  // #050506
    static let cwBgMid     = Color(red: 0.043, green: 0.043, blue: 0.051)  // #0B0B0D
    static let cwBgTop     = Color(red: 0.098, green: 0.102, blue: 0.125)  // #191A20
    static let cwBg        = Color(red: 0.055, green: 0.055, blue: 0.071)  // #0E0E12

    // Glass surfaces
    static let cwSurface1    = Color(red: 0.094, green: 0.094, blue: 0.125) // #181820
    static let cwSurface2    = Color(red: 0.122, green: 0.122, blue: 0.157) // #1F1F28
    static let cwSurfaceCard = Color(red: 0.086, green: 0.086, blue: 0.110).opacity(0.62) // glass card fill

    // Borders
    static let cwBorder       = Color.white.opacity(0.08)
    static let cwBorderStrong = Color.white.opacity(0.14)
    static let cwBorderCard   = Color.white.opacity(0.10)

    // Foregrounds
    static let cwFg1 = Color.white.opacity(0.95)
    static let cwFg2 = Color.white.opacity(0.62)
    static let cwFg3 = Color.white.opacity(0.42)

    // Brand accent (default — runtime value lives in PreferencesStore.accent)
    static let cwAccent          = Color(red: 0.486, green: 0.302, blue: 1.0)  // #7C4DFF
    static let cwAccentSecondary = Color(red: 0.302, green: 0.373, blue: 1.0)  // #4D5FFF

    // Curated accent presets — these are the swatches the user picks from on
    // the Customization tab. Hex values are mirrored in `AccentPreset.presets`.
    static let cwPresetViolet  = Color(red: 0.486, green: 0.302, blue: 1.000)  // #7C4DFF
    static let cwPresetMagenta = Color(red: 0.910, green: 0.298, blue: 0.788)  // #E84CC9
    static let cwPresetCrimson = Color(red: 1.000, green: 0.231, blue: 0.361)  // #FF3B5C
    static let cwPresetAmber   = Color(red: 1.000, green: 0.608, blue: 0.231)  // #FF9B3B
    static let cwPresetMint    = Color(red: 0.231, green: 0.831, blue: 0.651)  // #3BD4A6
    static let cwPresetCobalt  = Color(red: 0.231, green: 0.510, blue: 0.965)  // #3B82F6

    // Semantic aliases — read these from feature code instead of the preset
    // names so the meaning is obvious at the call site.
    static let cwSuccess = cwPresetMint
    static let cwWarning = cwPresetAmber
    static let cwDanger  = cwPresetCrimson
    static let cwInfo    = cwPresetCobalt
}

// MARK: - Backdrop gradient

extension LinearGradient {
    /// Vertical gradient backdrop for the whole Settings window. Top is the
    /// slightly-lit `cwBgTop`, bottom is the near-black `cwBgDeepest`. The
    /// accent radial glows are painted on top of this in `SettingsView`.
    static var cwBackdrop: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .cwBgTop,     location: 0.0),
                .init(color: .cwBgMid,     location: 0.55),
                .init(color: .cwBgDeepest, location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - v2 typography
//
// Same Monaspace Krypton family the legacy `kr*` helpers use, but exposed
// through a flatter API — `CWFont.mono(size:weight:)` — and a numeric size
// ramp (s9 / s10 / s11 / s12 / s13 / s14 / s17 / s20 / s22 / s26) that
// mirrors the design system's `--fs-*` CSS variables.

enum CWFont {
    static let family = "MonaspaceKrypton-Regular"

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium:                  name = "MonaspaceKrypton-Medium"
        case .semibold:                name = "MonaspaceKrypton-SemiBold"
        case .bold, .heavy, .black:    name = "MonaspaceKrypton-Bold"
        default:                       name = "MonaspaceKrypton-Regular"
        }
        return .custom(name, size: size)
    }

    // Ramp (matches --fs-* in colors_and_type.css)
    static let s9:  CGFloat = 9
    static let s10: CGFloat = 10
    static let s11: CGFloat = 11
    static let s12: CGFloat = 12
    static let s13: CGFloat = 13
    static let s14: CGFloat = 14
    static let s17: CGFloat = 17
    static let s20: CGFloat = 20
    static let s22: CGFloat = 22
    static let s26: CGFloat = 26
}

// MARK: - Spacing / radii / motion

enum CWSpace {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 32
}

enum CWRadius {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 7
    static let md:   CGFloat = 10
    static let lg:   CGFloat = 12       // glass cards
    static let xl:   CGFloat = 14       // window
    static let pill: CGFloat = 999
}

extension Animation {
    /// Snappy motion for hover / press feedback — under 150ms so taps feel direct.
    static var cwFast: Animation { .timingCurve(0.16, 0.84, 0.30, 1.0, duration: 0.120) }
    /// Standard motion for tab transitions, sheet swaps, sidebar selection.
    static var cwMain: Animation { .timingCurve(0.16, 0.84, 0.30, 1.0, duration: 0.220) }
}

// Note: `Color(hex:)` already exists in `Color+Hex.swift` (more capable —
// also handles 8-char `RRGGBBAA`). The v2 design system expects a 6-char
// `Color(hex:)` initialiser; the production helper satisfies that interface,
// so no duplicate is added here.

// MARK: - Card

/// The shared rounded card that wraps each tab's content sections. Flat dark
/// fill + hairline border in the divider color — matches the mockup's
/// "raised slate" look without any drop shadow or blur. Defaults pulled from
/// the design tokens so future tweaks ripple through every tab.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var padding: CGFloat = 0
    var cornerRadius: CGFloat = SettingsDesign.cardCornerRadius

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
                    .strokeBorder(SettingsDesign.cardStroke,
                                  lineWidth: SettingsDesign.cardBorderWidth)
            )
    }
}

/// A row inside a `SettingsCard` — title + description on the left, free-form
/// trailing content (toggle, dropdown, button, badges) on the right.
/// Vertical padding matches the mockup's generous breathing room. Uses
/// the shared spacing tokens so every row in every tab reads at the same
/// rhythm.
struct CardRow<Trailing: View>: View {
    let title: String
    let description: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SettingsDesign.krBody(size: 13.5, weight: .medium))
                    .foregroundStyle(SettingsDesign.textPrimary)
                if let description, !description.isEmpty {
                    Text(description)
                        .font(SettingsDesign.krCaption(size: 11.5))
                        .foregroundStyle(SettingsDesign.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 14)
            trailing()
        }
        .padding(.horizontal, SettingsDesign.rowPaddingHorizontal)
        .padding(.vertical, SettingsDesign.rowPaddingVertical)
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
/// text so they sit inline with the label — that's the retro-terminal cue.
/// A thin border in the accent color wraps the whole thing. Letter-spaced
/// for a typographic "stamp" feel.
struct TerminalBadge: View {
    let label: String
    /// Optional leading glyph rendered between the opening bracket and the
    /// label. Examples: "▪", "↓", "□", "*", "•", "#". Pass `nil` for a
    /// label-only badge like `[ ACTIVE ]`.
    var glyph: String?
    let tint: Color
    /// Size of the badge text. Smaller for inline-with-title contexts
    /// (Models / About), larger for stand-alone use.
    var size: CGFloat = 10.5

    var body: some View {
        HStack(spacing: 6) {
            Text("[")
                .foregroundStyle(tint.opacity(0.85))
            if let glyph {
                Text(glyph)
                    .foregroundStyle(tint)
            }
            Text(label)
                .foregroundStyle(tint)
                .tracking(0.8)
            Text("]")
                .foregroundStyle(tint.opacity(0.85))
        }
        .font(SettingsDesign.krBadge(size: size))
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                )
        )
    }
}

// MARK: - Native macOS button

/// Deliberately-plain white macOS-style button. Used for the action buttons in
/// each row (`[Switch]`, `[In use]`, `[Download]`, `[Configure…]`, etc).
/// The retro-terminal aesthetic everywhere else makes these buttons stand
/// out as the clickable affordances — same trick as Tailscale's macOS
/// settings. Per the design spec, the literal square brackets are baked
/// into the label text by the caller.
struct NativeMacButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(
                isEnabled
                    ? Color(red: 0.067, green: 0.067, blue: 0.067)
                    : Color(red: 0.45, green: 0.45, blue: 0.45)
            )
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        isEnabled
                            ? (configuration.isPressed
                                ? Color(red: 0.82, green: 0.82, blue: 0.82)
                                : Color(red: 0.95, green: 0.95, blue: 0.95))
                            : Color(red: 0.86, green: 0.86, blue: 0.86)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(red: 0.70, green: 0.70, blue: 0.70),
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

// MARK: - Dropdown button

/// Compact pull-down used for any "pick one from a small list" row in
/// Settings (Activation mode, Dictation language, etc). Consistent styling
/// — soft white fill, hairline border, chevron on the right — so different
/// tabs don't end up with subtly different dropdowns.
struct DropdownOption: Identifiable {
    let id = UUID()
    let label: String
    let isSelected: Bool
    let action: () -> Void
}

struct DropdownButton: View {
    let currentLabel: String
    let options: [DropdownOption]
    /// When false, renders dimmed and ignores clicks. The trigger still
    /// shows so the affordance is visible.
    var enabled: Bool = true

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(action: option.action) {
                    HStack {
                        Text(option.label)
                        if option.isSelected {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentLabel)
                    .font(SettingsDesign.krBody(size: 12.5, weight: .medium))
                    .foregroundStyle(enabled
                                     ? SettingsDesign.textPrimary
                                     : SettingsDesign.textTertiary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(enabled
                                     ? SettingsDesign.textSecondary
                                     : SettingsDesign.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(enabled ? 0.05 : 0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(SettingsDesign.divider.opacity(enabled ? 1.0 : 0.4),
                                          lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!enabled)
        .fixedSize()
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
