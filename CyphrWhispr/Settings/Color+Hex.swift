import SwiftUI
import AppKit

/// Lossy hex <-> SwiftUI.Color helpers used by the user-controlled accent
/// system. We persist the chosen accent as a hex string in UserDefaults and
/// reconstitute a SwiftUI.Color on read; that's much friendlier than blobbing
/// a Codable color and survives Color's API changes between OS versions.
extension Color {
    /// Parse a `#RRGGBB`, `RRGGBB`, `#RRGGBBAA`, or `RRGGBBAA` string. Returns
    /// nil for malformed input so callers can fall back to a default.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >>  8) & 0xFF) / 255
            b = Double( value        & 0xFF) / 255
            a = 1
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >>  8) & 0xFF) / 255
            a = Double( value        & 0xFF) / 255
        }
        self = Color(red: r, green: g, blue: b, opacity: a)
    }

    /// Convert back to `#RRGGBB`. Always sRGB so two round-trips give the same
    /// string. Drops alpha — accent colors are always fully opaque in the UI.
    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((nsColor.redComponent   * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent  * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Shift the hue by `delta` degrees (and optionally tweak saturation /
    /// brightness). We use this to derive the "secondary" accent — the cooler
    /// counterpart that the pill's comet gradient and the shortcut field's
    /// glow stroke fade INTO. Deriving rather than asking the user to pick
    /// two colors keeps the picker a single decision but still gives the
    /// gradients somewhere to go so they don't read as flat.
    func huedShift(by deltaDegrees: CGFloat,
                   saturationDelta: CGFloat = 0,
                   brightnessDelta: CGFloat = 0) -> Color {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? .blue
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var newH = (h + deltaDegrees / 360).truncatingRemainder(dividingBy: 1)
        if newH < 0 { newH += 1 }
        let newS = min(max(s + saturationDelta, 0), 1)
        let newB = min(max(b + brightnessDelta, 0), 1)
        return Color(hue: Double(newH),
                     saturation: Double(newS),
                     brightness: Double(newB),
                     opacity: Double(a))
    }
}
