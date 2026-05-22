import SwiftUI

// Bracketed terminal-style label — the cypherpunk badge that lives in
// every Settings tab. Replaces the legacy `TerminalBadge`. House rule:
// never invent a new pill style anywhere in Settings — always reach for
// a `CWToken` first.
//
//     [ ▮ ACTIVE ]
//     [ ↓ DOWNLOADED ]
//     [ ⌗ ENCRYPTED ]

enum CWTokenVariant {
    case active        // accent (live — only this variant follows the user's accent)
    case custom        // lavender
    case downloaded    // mint
    case recommended   // amber
    case missing       // crimson + hollow indicator
    case local         // mint
    case encrypted     // cobalt
    case foss          // magenta
    case info          // cobalt
    case meta          // white@55%

    var staticColor: Color {
        switch self {
        case .active, .custom:    return .cwPresetViolet
        case .downloaded, .local: return .cwPresetMint
        case .recommended:        return .cwPresetAmber
        case .missing:            return .cwPresetCrimson
        case .encrypted, .info:   return .cwPresetCobalt
        case .foss:               return .cwPresetMagenta
        case .meta:               return Color.white.opacity(0.55)
        }
    }

    var followsAccent: Bool { self == .active }
}

enum CWTokenIndicator {
    case block
    case hollow
    case glyph(String)
    case none
}

enum CWTokenSize { case sm, md, lg }

struct CWToken: View {
    let text: String
    var variant: CWTokenVariant = .info
    var indicator: CWTokenIndicator = .none
    var live: Bool = false
    var size: CWTokenSize = .md

    @EnvironmentObject private var prefs: PreferencesStore

    private var tone: Color {
        variant.followsAccent ? prefs.accent : variant.staticColor
    }

    private var fontSize: CGFloat {
        switch size { case .sm: return 9; case .md: return 11; case .lg: return 13 }
    }
    private var hPad: CGFloat { size == .sm ? 7 : (size == .lg ? 12 : 9) }
    private var vPad: CGFloat { size == .sm ? 2 : (size == .lg ? 6  : 4) }
    private var gap:  CGFloat { size == .sm ? 4 : (size == .lg ? 8  : 6) }
    private var blk:  CGFloat { size == .sm ? 5 : (size == .lg ? 9  : 7) }

    var body: some View {
        HStack(spacing: gap) {
            bracket("[")
            indicatorView
            Text(text.uppercased())
                .foregroundColor(tone)
                .tracking(fontSize * 0.10)
            if live { Caret(color: tone, height: fontSize) }
            bracket("]")
        }
        .font(CWFont.mono(size: fontSize, weight: .semibold))
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 3).stroke(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .cwIf(variant == .active) { v in
            v.shadow(color: tone.opacity(0.35), radius: 6, x: 0, y: 0)
        }
        .fixedSize()
    }

    @ViewBuilder private var indicatorView: some View {
        switch indicator {
        case .block:
            Rectangle().fill(tone).frame(width: blk, height: blk)
                .shadow(color: tone.opacity(0.6), radius: 3)
        case .hollow:
            Rectangle().strokeBorder(tone, lineWidth: 1).frame(width: blk, height: blk)
        case .glyph(let g):
            Text(g)
                .font(CWFont.mono(size: fontSize * 0.95, weight: .semibold))
                .foregroundColor(tone)
        case .none: EmptyView()
        }
    }

    private func bracket(_ ch: String) -> some View {
        Text(ch).foregroundColor(tone.opacity(0.55)).fontWeight(.medium)
    }

    private var background: Color {
        variant == .active ? tone.opacity(0.18) : Color.white.opacity(0.04)
    }
    private var border: Color {
        variant == .active ? tone.opacity(0.55) : Color.white.opacity(0.10)
    }
}

/// Blinking caret used inside `CWToken` when `live: true`. Roughly half the
/// text height, alternates opacity every ~525ms.
private struct Caret: View {
    let color: Color
    let height: CGFloat
    @State private var on = true
    var body: some View {
        Rectangle().fill(color)
            .frame(width: max(4, height * 0.5), height: height)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.linear(duration: 0.525).repeatForever(autoreverses: true)) {
                    on.toggle()
                }
            }
            .accessibilityHidden(true)
    }
}

/// Conditional view modifier — wraps a view only when `cond` is true.
/// Namespaced as `cwIf` to avoid colliding with any project-wide `if`
/// extension callers might add later.
extension View {
    @ViewBuilder
    func cwIf<C: View>(_ cond: Bool, transform: (Self) -> C) -> some View {
        if cond { transform(self) } else { self }
    }
}
