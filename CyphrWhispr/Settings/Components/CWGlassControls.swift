import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Section header
//
// Top-of-page title + secondary subtitle used by every tab. Sits inside
// the tab's content stack, NOT inside a Card3. The negative tracking on
// the title comes from the design spec — Monaspace Krypton at 22pt reads
// a touch loose without it.

struct SectionHead3: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CWFont.mono(size: CWFont.s22, weight: .semibold))
                .tracking(-0.22)
                .foregroundColor(.cwFg1)
            if let subtitle {
                Text(subtitle)
                    .font(CWFont.mono(size: CWFont.s13, weight: .regular))
                    .foregroundColor(.cwFg2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, CWSpace.s5)
    }
}

// MARK: - Glass card
//
// Three layers stack to produce the "liquid glass" surface:
//   1. NSVisualEffectView (material: .hudWindow, blending: .withinWindow)
//      — actual GPU-backed backdrop blur.
//   2. cwSurfaceCard tint (0.62α dark) over the blur so the card reads
//      consistently against any backdrop.
//   3. Hairline cwBorder + a top-edge inner highlight blended with
//      .plusLighter — the "concave glass" lift.

struct Card3<Content: View>: View {
    var title: String? = nil
    var meta: String?  = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                HStack(spacing: 10) {
                    Text(title.uppercased())
                        .tracking(1.7)
                        .foregroundColor(.cwFg3)
                    Spacer()
                    if let meta {
                        Text(meta.uppercased())
                            .tracking(1.6)
                            .foregroundColor(.cwFg3)
                    }
                }
                .font(CWFont.mono(size: CWFont.s10, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(Rectangle().fill(Color.cwBorder).frame(height: 1), alignment: .bottom)
            }
            content
        }
        .background(
            ZStack {
                #if os(macOS)
                VisualEffectBlur(material: .hudWindow, blending: .withinWindow)
                    .opacity(0.55)
                #endif
                Color.cwSurfaceCard
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: CWRadius.lg).stroke(Color.cwBorder, lineWidth: 1)
        )
        .overlay(
            // Top inner highlight (the glass "lift")
            RoundedRectangle(cornerRadius: CWRadius.lg)
                .stroke(LinearGradient(
                    colors: [Color.white.opacity(0.06), .clear],
                    startPoint: .top, endPoint: .center
                ), lineWidth: 1)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: CWRadius.lg))
        .shadow(color: .black.opacity(0.20), radius: 24, x: 0, y: 8)
        .padding(.bottom, CWSpace.s4)
    }
}

#if os(macOS)
/// Thin NSVisualEffectView wrapper. Used inside `Card3` and anywhere else
/// that needs real backdrop blur instead of SwiftUI's `.regularMaterial`
/// approximation (which on dark UI looks washed-out without a tint layer
/// on top).
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}
#endif

// MARK: - Row inside a card
//
// Label + sub on the left, free-form trailing control on the right.
// `isLast` suppresses the bottom hairline so the card's outer border
// is the only line under the last row.

struct Row3<Control: View>: View {
    let label: String
    var sub: String? = nil
    var isLast: Bool = false
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: CWSpace.s4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(CWFont.mono(size: CWFont.s13, weight: .medium))
                    .foregroundColor(.cwFg1)
                if let sub {
                    Text(sub)
                        .font(CWFont.mono(size: CWFont.s11, weight: .regular))
                        .foregroundColor(.cwFg3)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.cwBorder).frame(height: 1)
            }
        }
    }
}

// MARK: - Toggle (Apple-style glass pill)
//
// Custom toggle because SwiftUI's `Toggle(...)` doesn't expose enough
// styling control to match the brand accent + soft glow. The thumb is a
// radial-gradient circle with a dropped shadow; the track flips between
// neutral white-on-dark and an accent gradient with a 8pt outer glow.

struct Toggle3: View {
    @Binding var isOn: Bool
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        Button {
            withAnimation(.cwMain) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn
                          ? AnyShapeStyle(LinearGradient(colors: [prefs.accent.opacity(0.92), prefs.accent],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(LinearGradient(colors: [Color.white.opacity(0.04),
                                                                   Color.white.opacity(0.02)],
                                                          startPoint: .top, endPoint: .bottom)))
                    .overlay(
                        Capsule().stroke(isOn ? prefs.accent.opacity(0.55)
                                              : Color.white.opacity(0.10),
                                         lineWidth: 1)
                    )
                    .shadow(color: isOn ? prefs.accent.opacity(0.40) : .clear,
                            radius: 8, x: 0, y: 0)

                Circle()
                    .fill(RadialGradient(
                        colors: [.white, Color(red: 0.925, green: 0.925, blue: 0.937),
                                 Color(red: 0.843, green: 0.843, blue: 0.863)],
                        center: .top, startRadius: 0, endRadius: 22))
                    .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.5))
                    .frame(width: 19, height: 19)
                    .shadow(color: .black.opacity(0.30), radius: 1.5, x: 0, y: 1)
                    .padding(2)
            }
            .frame(width: 42, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

// MARK: - Segmented control
//
// Two- or three-option picker. Active option gets a translucent white
// fill + cwBorderStrong outline; inactive options are plain text.

struct Segmented3<T: Hashable>: View {
    @Binding var value: T
    let options: [(value: T, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { opt in
                Button { value = opt.value } label: {
                    Text(opt.label)
                        .font(CWFont.mono(size: CWFont.s12, weight: opt.value == value ? .medium : .regular))
                        .foregroundColor(opt.value == value ? .cwFg1 : .cwFg2)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            ZStack {
                                if opt.value == value {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(LinearGradient(
                                            colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                                            startPoint: .top, endPoint: .bottom))
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.cwBorderStrong, lineWidth: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Color.cwBorder, lineWidth: 1)
        )
    }
}

// MARK: - Shortcut display (glass key caps)
//
// Visual-only: renders a list of key labels as raised glass key caps in
// a shared container. Production uses `KeyboardShortcuts.Recorder` for
// the actual capture — this component is what the Shortcut row's button
// label wraps when not in recording mode (and what wraps the recorder
// when it is).

struct Shortcut3: View {
    let keys: [String]
    var focused: Bool = false
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                Text(k)
                    .font(CWFont.mono(size: CWFont.s12, weight: .medium))
                    .foregroundColor(.cwFg1)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                                startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.cwBorderStrong, lineWidth: 1))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.white.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(focused ? prefs.accent : Color.cwBorder, lineWidth: 1)
        )
        .shadow(color: focused ? prefs.accent.opacity(0.30) : .clear, radius: 8)
    }
}

// MARK: - Accent presets

/// One of the six curated accent options surfaced on the Customization tab.
/// Hexes mirror the `Color.cwPreset*` constants exactly.
struct AccentPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
    let hex: String

    static let presets: [AccentPreset] = [
        .init(id: "violet",  name: "Violet",  color: .cwPresetViolet,  hex: "#7C4DFF"),
        .init(id: "magenta", name: "Magenta", color: .cwPresetMagenta, hex: "#E84CC9"),
        .init(id: "crimson", name: "Crimson", color: .cwPresetCrimson, hex: "#FF3B5C"),
        .init(id: "amber",   name: "Amber",   color: .cwPresetAmber,   hex: "#FF9B3B"),
        .init(id: "mint",    name: "Mint",    color: .cwPresetMint,    hex: "#3BD4A6"),
        .init(id: "cobalt",  name: "Cobalt",  color: .cwPresetCobalt,  hex: "#3B82F6"),
    ]
}

// MARK: - Swatch picker
//
// One circular preset chip in the accent grid. Selection state shows a
// white ring + outer glow in the preset's own colour.

struct Swatch3: View {
    let preset: AccentPreset
    @Binding var accentHex: String

    private var selected: Bool {
        accentHex.caseInsensitiveCompare(preset.hex) == .orderedSame
    }

    var body: some View {
        Button { accentHex = preset.hex } label: {
            Circle()
                .fill(preset.color)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
                        .blendMode(.plusLighter)
                )
                .padding(4)
                .overlay(
                    Circle().stroke(selected ? Color.white : .clear, lineWidth: 1.5)
                )
                .background(
                    Circle().stroke(selected ? preset.color : .clear, lineWidth: 1)
                        .padding(2)
                )
                .shadow(color: selected ? preset.color.opacity(0.55) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .help(preset.name)
    }
}

// MARK: - Custom hex picker

#if os(macOS)
/// Embeds a borderless `NSColorWell` so users get the full macOS colour
/// panel (drag-droppable, eyedropper, sliders). On change, the picked
/// colour is round-tripped to sRGB and written back as a `#RRGGBB` hex
/// string into `PreferencesStore.accentHex`.
struct HexPicker3: View {
    @Binding var hex: String

    var body: some View {
        HStack(spacing: 10) {
            ColorWell(hex: $hex)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.20), lineWidth: 1))

            Text(hex.uppercased())
                .font(CWFont.mono(size: CWFont.s12, weight: .medium))
                .tracking(0.6)
                .foregroundColor(.cwFg1)
        }
        .padding(.leading, 4).padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.white.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cwBorder, lineWidth: 1))
    }
}

private struct ColorWell: NSViewRepresentable {
    @Binding var hex: String

    func makeCoordinator() -> Coordinator { Coordinator(hex: $hex) }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.isBordered = false
        well.color = NSColor(Color(hex: hex) ?? .cwAccent)
        well.target = context.coordinator
        well.action = #selector(Coordinator.changed(_:))
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        nsView.color = NSColor(Color(hex: hex) ?? .cwAccent)
    }

    final class Coordinator: NSObject {
        var hex: Binding<String>
        init(hex: Binding<String>) { self.hex = hex }
        @objc func changed(_ well: NSColorWell) {
            guard let rgb = well.color.usingColorSpace(.sRGB) else { return }
            let r = Int((rgb.redComponent   * 255).rounded())
            let g = Int((rgb.greenComponent * 255).rounded())
            let b = Int((rgb.blueComponent  * 255).rounded())
            hex.wrappedValue = String(format: "#%02X%02X%02X", r, g, b)
        }
    }
}
#endif
