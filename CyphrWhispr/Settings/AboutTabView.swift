import SwiftUI
import AppKit

/// Settings → About tab. Brand panel + accent-color picker + four-feature
/// value prop + footer with version/links. Kept deliberately minimal — this
/// is a sticker, not a docs page.
struct AboutTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        // ScrollView so the layout stays usable when the user shrinks the
        // window vertically.
        ScrollView(.vertical, showsIndicators: false) {
            content
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 14) {
            // Brand card.
            SettingsCard {
                HStack(alignment: .center, spacing: 14) {
                    AppIconBadge(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CyphrWhispr")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(SettingsDesign.textPrimary)
                        Text("Local, private, fast speech-to-text\nfor any text field on your Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsDesign.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }

            // Accent color picker.
            AccentPickerCard()

            // Feature list — separate card.
            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "Private by default",
                        subtitle: "Everything stays on your device."
                    )
                    rowDivider
                    FeatureRow(
                        icon: "bolt.fill",
                        title: "Fast & local",
                        subtitle: "Optimized for Apple Silicon."
                    )
                    rowDivider
                    FeatureRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "Open source",
                        subtitle: "Transparent, auditable, community-driven."
                    )
                    rowDivider
                    FeatureRow(
                        icon: "heart.fill",
                        title: "Built with care",
                        subtitle: "For creators, researchers, and privacy champions."
                    )
                }
            }

            Spacer(minLength: 0)

            // Footer.
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(version) (\(build))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsDesign.textPrimary)
                    Text("© 2026 CyphrWhispr. All rights reserved.")
                        .font(.system(size: 10))
                        .foregroundStyle(SettingsDesign.textTertiary)
                }
                Spacer()
                Button {
                    if let url = URL(string: "https://cyphrwhispr.app") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Website")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(GhostButtonStyle())

                Button("Check for updates") {
                    // Wired to Sparkle (or equivalent) in a future phase.
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .overlay(SettingsDesign.cardStroke)
            .padding(.horizontal, 16)
    }
}

// MARK: - Brand badge

/// Small rounded-square that shows the CyphrWhispr logo (down-triangle +
/// filled circle) on a dark gradient background — a miniature of the app
/// icon that doesn't require pulling pixels out of `Assets.xcassets`.
private struct AppIconBadge: View {
    var size: CGFloat = 64

    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        SettingsDesign.bgTop,
                        Color.black,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(prefs.accent.opacity(0.40), lineWidth: 1)
            )
            .shadow(color: prefs.accent.opacity(0.45), radius: 14, x: 0, y: 0)
            .frame(width: size, height: size)
            .overlay(
                HStack(spacing: size * 0.06) {
                    Image(systemName: "play.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(90))
                        .frame(width: size * 0.26, height: size * 0.26)
                        .foregroundStyle(.white)
                    Circle()
                        .fill(.white)
                        .frame(width: size * 0.24, height: size * 0.24)
                }
            )
    }
}

// MARK: - Accent color picker

/// Lets the user repaint every accent in the app — Settings tabs, the active
/// row chips, the pill's comet halo — by picking a new color. Six curated
/// presets (the violet ships as default) for one-click change, plus a system
/// `ColorPicker` for "I want something exact."
private struct AccentPickerCard: View {
    @EnvironmentObject private var prefs: PreferencesStore

    /// Curated swatches. Hand-picked to look good on dark glass with the same
    /// rim-glow treatment as the brand violet — saturated mid-tones, no
    /// pastels, no muddy darks. Order goes warm → cool → green so the row
    /// reads as a spectrum.
    private static let presets: [(name: String, hex: String)] = [
        ("Violet",  "#7C4DFF"),
        ("Magenta", "#E84CC9"),
        ("Crimson", "#FF3B5C"),
        ("Amber",   "#FF9B3B"),
        ("Mint",    "#3BD4A6"),
        ("Cobalt",  "#3B82F6"),
    ]

    /// Bridges SwiftUI's ColorPicker (which wants a `Binding<Color>`) into our
    /// hex-backed prefs. Reads compute from `accent`, writes go through
    /// `setAccent` so we keep the round-trip-safe hex form.
    private var colorBinding: Binding<Color> {
        Binding(
            get: { prefs.accent },
            set: { prefs.setAccent($0) }
        )
    }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    SettingsIconBadge(systemName: "paintpalette.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accent color")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SettingsDesign.textPrimary)
                        Text("Personalize highlights, glows, and active states.")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsDesign.textSecondary)
                    }
                    Spacer()
                }

                // Preset row. HStack with even spacing so the swatches read as
                // siblings rather than a list.
                HStack(spacing: 10) {
                    ForEach(Self.presets, id: \.hex) { preset in
                        SwatchButton(
                            color: Color(hex: preset.hex) ?? PreferencesStore.defaultAccent,
                            isSelected: prefs.accentHex.caseInsensitiveCompare(preset.hex) == .orderedSame,
                            label: preset.name
                        ) {
                            prefs.accentHex = preset.hex
                        }
                    }

                    // System ColorPicker for free-form choice. Hides its own
                    // label so we can wrap a SwatchButton-shaped trigger
                    // around a tiny invisible picker for a consistent look.
                    ColorPicker("Custom accent", selection: colorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 26, height: 26)
                        .help("Pick a custom accent color")
                }

                HStack {
                    Text("Current: \(prefs.accentHex.uppercased())")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(SettingsDesign.textTertiary)
                    Spacer()
                    if prefs.accentHex.caseInsensitiveCompare(PreferencesStore.defaultAccentHex) != .orderedSame {
                        Button("Reset to brand violet") {
                            prefs.resetAccent()
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
            }
        }
    }
}

/// One circular swatch in the preset row. Renders the chosen color with a
/// subtle inner gradient so it looks like a chip, not a flat dot, and shows
/// a white hairline + matching glow when selected.
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
                        // Gentle top-down highlight so the swatch reads as
                        // dimensional rather than a paint chip.
                        LinearGradient(
                            colors: [color.opacity(0.95), color],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0.18),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: color.opacity(isSelected ? 0.65 : 0.0),
                            radius: isSelected ? 8 : 0, x: 0, y: 0)
                    .frame(width: 26, height: 26)
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Feature row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(systemName: icon, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsDesign.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsDesign.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsDesign.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
