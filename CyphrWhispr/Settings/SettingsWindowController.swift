import AppKit
import SwiftUI

/// Manages the Settings window manually instead of relying on SwiftUI's
/// `Settings` scene + `showSettingsWindow:` selector. That selector is fragile
/// in `.accessory` (no-dock) apps because there's no key window to walk the
/// responder chain from, and on some macOS releases the action is silently
/// dropped. Hosting our own NSWindow + NSHostingController is 30 lines of code
/// and Just Works.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    /// Show (or bring to front) the Settings window. Brings the app forward so
    /// the window appears in front of whatever app the user was just in.
    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingController(
            rootView: SettingsView()
                .environmentObject(PreferencesStore.shared)
        )
        let window = NSWindow(contentViewController: host)
        window.title = "CyphrWhispr Settings"
        // .resizable lets the user drag the window edges; .fullSizeContentView
        // lets the SwiftUI gradient extend up behind the transparent titlebar.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        // Dark, transparent titlebar so the SwiftUI gradient bleeds up behind
        // the traffic lights — matches the design screenshots.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(SettingsDesign.pageBackground)
        window.isMovableByWindowBackground = true
        // Hard floor on size — the sidebar (260pt) + content panel needs at
        // least 880pt wide before rows start to feel cramped.
        window.minSize = NSSize(width: 880, height: 600)
        // Ideal first-launch size if no autosave entry exists yet. The
        // sidebar refactor needs more horizontal room than the old segmented
        // tab layout did.
        window.setContentSize(NSSize(width: 960, height: 720))
        window.center()
        // Autosaves position AND size between launches — the user's preferred
        // window dimensions stick even after a quit/relaunch.
        window.setFrameAutosaveName("CyphrWhisprSettingsWindow")
        // Clamp to whatever fraction of the current screen is reasonable for
        // a settings window — never larger than the visible frame minus a
        // generous margin.
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let maxW = min(window.frame.width, visible.width - 80)
            let maxH = min(window.frame.height, visible.height - 80)
            if maxW < window.frame.width || maxH < window.frame.height {
                let newFrame = NSRect(
                    x: visible.midX - maxW / 2,
                    y: visible.midY - maxH / 2,
                    width: maxW,
                    height: maxH
                )
                window.setFrame(newFrame, display: true)
            }
        }

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
