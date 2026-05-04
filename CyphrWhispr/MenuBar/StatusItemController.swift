import AppKit

@MainActor
final class StatusItemController {
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = makeLogoIcon()
            button.toolTip = "CyphrWhispr"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    func update(for state: AppState) {
        guard let button = statusItem?.button else { return }
        switch state {
        case .idle, .loadingModel:
            button.image = makeLogoIcon()
            button.toolTip = "CyphrWhispr"
        case .armed, .streaming, .finalizing, .injecting:
            // Same filled logo, just a tooltip change. The pill window itself
            // is the primary "I'm recording" signal — duplicating that in the
            // menu bar with a different glyph would just be visual noise.
            button.image = makeLogoIcon()
            button.toolTip = "CyphrWhispr — listening"
        case .error(let message):
            button.image = makeIcon(symbolName: "exclamationmark.triangle.fill")
            button.image?.isTemplate = true
            button.toolTip = "CyphrWhispr — \(message)"
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "CyphrWhispr", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(settingsTapped),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(
            title: "Quit CyphrWhispr",
            action: #selector(quitTapped),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func quitTapped() {
        onQuit?()
    }

    /// Open Settings via our manually-managed window controller.
    /// (We don't use SwiftUI's `Settings` scene + `showSettingsWindow:` action
    /// because it's flaky in accessory-activation apps with no key window.)
    @objc private func settingsTapped() {
        SettingsWindowController.shared.show()
    }

    private func makeIcon(symbolName: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "CyphrWhispr")?
            .withSymbolConfiguration(config)
        return image ?? NSImage()
    }

    /// Renders the CyphrWhispr logo (down-pointing triangle + filled circle)
    /// as a menu-bar template image. Drawn as solid filled shapes in pure
    /// black; AppKit auto-tints the template to match the menu bar's
    /// appearance — so on a dark menu bar the glyphs render as crisp white,
    /// and on a light menu bar they render as black, matching every other
    /// status-item icon on the system.
    ///
    /// Layout matches the in-pill icons: triangle on the left, filled circle
    /// on the right, both vertically centred. Sized for the standard 22pt
    /// menu-bar height with ~3pt vertical padding so the glyphs have
    /// breathing room.
    private func makeLogoIcon() -> NSImage {
        // 20×16 fits comfortably inside the 22pt status-bar slot.
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            // Triangle (left). Slightly rounded join so it reads as the same
            // shape as the in-pill DownTriangle.
            let triX: CGFloat = 1
            let triY: CGFloat = 4
            let triW: CGFloat = 8
            let triH: CGFloat = 7
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: triX,           y: triY + triH))
            triangle.line(to: NSPoint(x: triX + triW,    y: triY + triH))
            triangle.line(to: NSPoint(x: triX + triW/2,  y: triY))
            triangle.close()
            triangle.lineJoinStyle = .round
            triangle.lineCapStyle = .round

            // Circle (right). Same diameter as triangle width so the two read
            // as a balanced pair, mirroring the pill's interior.
            let circleD: CGFloat = 7
            let circleX: CGFloat = 11
            let circleY: CGFloat = 4 + (triH - circleD) / 2  // vertically aligned with triangle
            let circle = NSBezierPath(ovalIn: NSRect(
                x: circleX, y: circleY, width: circleD, height: circleD
            ))

            // Both glyphs always solid-filled. Template tinting handles the
            // actual on-screen colour (white on dark menu bars, black on
            // light) — drawing with NSColor.black is the conventional way to
            // produce a template image's alpha mask.
            NSColor.black.setFill()
            triangle.fill()
            circle.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
