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
        self.level = .statusBar

        // .canJoinAllSpaces: pill follows the user across Spaces
        // .fullScreenAuxiliary: pill stays visible in full-screen apps
        // .stationary: don't move during Mission Control
        // .fullScreenDisallowsTiling: prevents the macOS Sequoia/Tahoe window-
        //   tiling overlay (the two big rounded rectangles dividing the screen
        //   in half) from appearing when the user drags the pill near a screen
        //   edge. Without this, system tiling intercepts our drag.
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
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
