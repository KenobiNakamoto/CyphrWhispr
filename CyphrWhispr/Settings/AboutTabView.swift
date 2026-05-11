import SwiftUI
import AppKit

/// Settings → About — restyled to match the high-fidelity mockup.
/// Centered hero (app icon glow + name + version + description), followed by
/// a four-row card: Accent color swatch row, Source link, License badge,
/// Privacy badges.
struct AboutTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .center, spacing: 32) {
                hero
                aboutCard
                    .frame(maxWidth: 760)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            AppIconHero(size: 128)
            Text("CyphrWhispr")
                .font(SettingsDesign.krPageTitle(size: 32))
                .foregroundStyle(SettingsDesign.textPrimary)
            Text("v\(version) · Build \(build)")
                .font(SettingsDesign.krCaption(size: 12))
                .foregroundStyle(SettingsDesign.textTertiary)
                .padding(.top, -4)
            Text("A native macOS dictation widget — local, encrypted, and intentionally minimal. Press a key, speak, watch words land at your cursor.")
                .font(SettingsDesign.krPageSubtitle(size: 13))
                .foregroundStyle(SettingsDesign.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)
                .padding(.top, 6)
        }
    }

    // MARK: - About card (4 rows)

    private var aboutCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                accentRow
                CardRowDivider()
                sourceRow
                CardRowDivider()
                licenseRow
                CardRowDivider()
                privacyRow
            }
        }
    }

    private var accentRow: some View {
        CardRow(
            title: "Accent colour",
            description: "Used by the pill's comet rim and the Settings chrome."
        ) {
            AccentSwatchRow()
        }
    }

    private var sourceRow: some View {
        CardRow(
            title: "Source",
            description: "github.com/KenobiNakamoto/CyphrWhispr"
        ) {
            Button("View on GitHub") {
                if let url = URL(string: "https://github.com/KenobiNakamoto/CyphrWhispr") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(NativeMacButtonStyle())
        }
    }

    private var licenseRow: some View {
        CardRow(
            title: "License",
            description: nil
        ) {
            TerminalBadge(label: "MIT", glyph: "*", tint: SettingsDesign.badgeMagenta)
        }
    }

    private var privacyRow: some View {
        CardRow(
            title: "Privacy",
            description: nil
        ) {
            HStack(spacing: 8) {
                TerminalBadge(label: "100% LOCAL",
                              glyph: "•",
                              tint: SettingsDesign.badgeSuccess)
                TerminalBadge(label: "ENCRYPTED",
                              glyph: "#",
                              tint: SettingsDesign.badgeBlue)
            }
        }
    }
}

// MARK: - App icon hero

/// Centered, glowing app icon — the focal point of the About hero. Renders
/// the same down-triangle + filled-circle glyph pair used in the menu bar,
/// scaled up onto a dark rounded square with an accent glow. Matches the
/// mockup's "icon with purple rim" exactly.
private struct AppIconHero: View {
    var size: CGFloat = 128

    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.10, blue: 0.13),
                        Color.black,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(prefs.accent.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(color: prefs.accent.opacity(0.50), radius: 24, x: 0, y: 0)
            .frame(width: size, height: size)
            .overlay(
                HStack(spacing: size * 0.07) {
                    Image(systemName: "play.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(90))
                        .frame(width: size * 0.24, height: size * 0.24)
                        .foregroundStyle(.white)
                    Circle()
                        .fill(.white)
                        .frame(width: size * 0.22, height: size * 0.22)
                }
            )
    }
}

// MARK: - Accent swatch row

/// Six circular swatches + a custom-color picker. The currently-selected
/// swatch grows slightly and gets a white inner ring + accent glow; click
/// any swatch to make it the new app-wide accent.
private struct AccentSwatchRow: View {
    @EnvironmentObject private var prefs: PreferencesStore

    /// Curated palette — saturated mid-tones that all look good on dark
    /// glass with the same rim-glow treatment. Same six as before; the
    /// brand violet ships as default. Order goes warm → cool so the row
    /// reads as a spectrum.
    private static let presets: [(name: String, hex: String)] = [
        ("Violet",  "#7C4DFF"),
        ("Magenta", "#E84CC9"),
        ("Crimson", "#FF3B5C"),
        ("Amber",   "#FF9B3B"),
        ("Mint",    "#3BD4A6"),
        ("Cobalt",  "#3B82F6"),
    ]

    private var colorBinding: Binding<Color> {
        Binding(
            get: { prefs.accent },
            set: { prefs.setAccent($0) }
        )
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Self.presets, id: \.hex) { preset in
                SwatchButton(
                    color: Color(hex: preset.hex) ?? PreferencesStore.defaultAccent,
                    isSelected: prefs.accentHex.caseInsensitiveCompare(preset.hex) == .orderedSame,
                    label: preset.name
                ) {
                    prefs.accentHex = preset.hex
                }
            }
            // System color picker for "I want something exact" — hidden
            // behind a discreet trailing button so it doesn't dominate the
            // curated row.
            ColorPicker("Custom accent", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
                .help("Pick a custom accent color")
        }
    }
}

/// One circular swatch in the preset row. The selected one grows ~10%,
/// gains a white inner ring, and casts a glow in its own color.
private struct SwatchButton: View {
    let color: Color
    let isSelected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.95), color],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(isSelected ? 1.0 : 0.18),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: color.opacity(isSelected ? 0.70 : 0.0),
                            radius: isSelected ? 10 : 0, x: 0, y: 0)
                    .frame(width: isSelected ? 30 : 26,
                           height: isSelected ? 30 : 26)
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
