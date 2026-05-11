import AppKit

@MainActor
final class StatusItemController {
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var hideObserver: NSObjectProtocol?

    /// Cached "last app state" so we can re-apply it after the menu-bar
    /// icon is hidden and then shown again. Without this, re-installing
    /// would put us back to `.idle` even if the user was mid-dictation
    /// when they flipped the toggle.
    private var lastState: AppState = .idle

    func install() {
        installStatusItem()

        // Hot-toggle support — observe the "hide menu bar icon" pref so the
        // user sees the icon disappear / reappear without quitting the app.
        if hideObserver == nil {
            hideObserver = NotificationCenter.default.addObserver(
                forName: .hideMenuBarIconDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.applyHidePref()
                }
            }
        }
        // Reflect the current pref state immediately on first install.
        applyHidePref()
    }

    /// Add the status item to the menu bar if we don't already have one,
    /// honouring the "hide menu bar icon" pref.
    private func installStatusItem() {
        guard statusItem == nil else { return }
        if PreferencesStore.shared.hideMenuBarIcon { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = makeLogoIcon()
            button.toolTip = "CyphrWhispr"
        }
        item.menu = buildMenu()
        statusItem = item
        // Re-apply the last known state so tooltip/icon match what the
        // coordinator was last broadcasting.
        update(for: lastState)
    }

    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        if let token = hideObserver {
            NotificationCenter.default.removeObserver(token)
            hideObserver = nil
        }
    }

    /// Reconcile the visible status item with the user's "hide menu bar
    /// icon" preference. Called once on install and again whenever the
    /// pref flips.
    private func applyHidePref() {
        let shouldHide = PreferencesStore.shared.hideMenuBarIcon
        if shouldHide {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        } else {
            installStatusItem()
        }
    }

    func update(for state: AppState) {
        // Remember the latest broadcast even if the icon is currently
        // hidden — we'll re-apply it next time it comes back.
        lastState = state
        guard let button = statusItem?.button else { return }
        switch state {
        case .idle, .loadingModel:
            button.image = makeLogoIcon()
            button.toolTip = "CyphrWhispr"
        case .spawning, .armed, .streaming, .finalizing, .injecting:
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
