import AppKit

/// Borderless, non-activating panel that floats above all apps including full-screen ones,
/// without stealing focus from whatever text field the user is dictating into.
final class PillPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        // `.popUpMenu` (NSPopUpMenuWindowLevel = 101) instead of
        // `.statusBar` (NSStatusWindowLevel = 25). On macOS 14+
        // (Sonoma/Sequoia), `.statusBar`-level non-activating panels
        // get "owned" by the Space they were created on and ignore
        // `.canJoinAllSpaces` — the pill ends up stuck on Space 1 even
        // after the user swipes to Space 2. `.popUpMenu` is a higher,
        // more system-wide level that the Spaces machinery treats as
        // "transient floating chrome" and lets the collection-behavior
        // flags actually take effect. The pill now follows across
        // Spaces correctly.
        self.level = .popUpMenu

        // .canJoinAllSpaces: pill follows the user across Spaces
        // .fullScreenAuxiliary: pill stays visible in full-screen apps
        // .fullScreenDisallowsTiling: prevents the macOS Sequoia/Tahoe window-
        //   tiling overlay (the two big rounded rectangles dividing the screen
        //   in half) from appearing when the user drags the pill near a screen
        //   edge. Without this, system tiling intercepts our drag.
        //
        // NOTE: `.stationary` was removed — it conflicts with
        // `.canJoinAllSpaces` in some macOS versions and was the second
        // half of the "pill stuck on Space 1" bug. With it removed and
        // the level bumped to `.popUpMenu`, the pill correctly appears
        // on whichever Space is currently active.
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .fullScreenDisallowsTiling,
        ]

        // We move the panel ourselves via DraggablePillView. Letting the system
        // also try to move it (isMovable / isMovableByWindowBackground) causes
        // both the tiling overlay and competing drag handlers, which manifested
        // as the snap-line breaking and the screen-half rectangles appearing.
        self.isMovable = false
        self.isMovableByWindowBackground = false

        self.hidesOnDeactivate = false
        self.hasShadow = false      // we draw our own shadow inside SwiftUI for a softer look
        self.backgroundColor = .clear
        self.isOpaque = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.becomesKeyOnlyIfNeeded = true
        self.animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
