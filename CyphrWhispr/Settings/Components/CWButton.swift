import SwiftUI

// Bracketed action button — same DNA as `CWToken`. Variants pick the tone
// (primary follows the user's accent, ghost is neutral, danger is crimson,
// etc.). The shape is the v3 glass design's flat translucent rectangle
// with a 1pt brand-tinted border and an offset-on-press micro-interaction.

enum CWButtonVariant {
    case primary, ghost, active, danger, foss, encrypted, downloaded, text

    var followsAccent: Bool { self == .primary || self == .active }
}

struct CWButton: View {
    let title: String
    var variant: CWButtonVariant = .primary
    var indicator: CWTokenIndicator = .none
    var live: Bool = false
    var action: () -> Void

    @EnvironmentObject private var prefs: PreferencesStore
    @State private var hovering = false
    @State private var pressed = false

    private var tone: Color {
        switch variant {
        case .primary, .active: return prefs.accent
        case .ghost, .text:     return .cwFg1
        case .danger:           return .cwPresetCrimson
        case .foss:             return .cwPresetMagenta
        case .encrypted:        return .cwPresetCobalt
        case .downloaded:       return .cwPresetMint
        }
    }

    private var fill: Color {
        switch variant {
        case .primary, .active: return prefs.accent.opacity(hovering ? 0.26 : 0.20)
        case .ghost:            return Color.white.opacity(hovering ? 0.08 : 0.04)
        case .text:             return .clear
        default:                return tone.opacity(0.10)
        }
    }

    private var border: Color {
        switch variant {
        case .text:    return .clear
        case .primary: return prefs.accent.opacity(0.55)
        default:       return hovering ? tone.opacity(0.55) : .cwBorderStrong
        }
    }

    private var label: Color {
        switch variant {
        case .primary, .active: return prefs.accent
        default:                return tone
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                bracket("[")
                indicatorView
                Text(title.uppercased()).tracking(1.1)
                if live {
                    Rectangle().fill(label)
                        .frame(width: 5, height: 10)
                }
                bracket("]")
            }
            .font(CWFont.mono(size: 11, weight: .semibold))
            .foregroundColor(label)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(fill)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .offset(y: pressed ? 1 : 0)
            .cwIf(variant == .primary) {
                $0.shadow(color: prefs.accent.opacity(0.30), radius: 6)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
    }

    @ViewBuilder private var indicatorView: some View {
        switch indicator {
        case .block:
            Rectangle().fill(label).frame(width: 6, height: 6)
        case .hollow:
            Rectangle().strokeBorder(label, lineWidth: 1).frame(width: 6, height: 6)
        case .glyph(let g):
            Text(g)
        case .none: EmptyView()
        }
    }

    private func bracket(_ ch: String) -> some View {
        Text(ch).foregroundColor(label.opacity(0.55)).fontWeight(.medium)
    }
}
