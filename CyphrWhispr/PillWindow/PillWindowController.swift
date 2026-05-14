import AppKit
import SwiftUI
import Combine

@MainActor
final class PillWindowController {
    /// True when the next `show()` should play the cinematic spawn instead of
    /// the instant fade-in. Set to `true` on init (so the first press of every
    /// session is cinematic) and again whenever the user picks a different
    /// Whisper model in Settings (because that triggers a fresh pre-warm and
    /// the same "first press" feel applies). Set to `false` after each spawn.
    private var spawnPending = true

    /// Held strongly so the observer survives for the controller's lifetime.
    private var modelChangeObserver: NSObjectProtocol?

    /// Total panel size. Bigger than the visible pill (170×48) because PillView
    /// pads itself so the drop shadow + rim halo can fully fade to alpha 0
    /// before reaching the panel boundary. Bumped ~30% over the previous
    /// 226×112 after a faint silhouette of the panel was still showing at the
    /// shadow's fall-off.
    /// Padding: 36 left/right/top, 48 bottom (extra for the y-offset shadow).
    /// Panel = 170+72 × 48+84 = 242×132.
    private static let pillSize = NSSize(width: 242, height: 132)
    /// Distance of the *visible pill's* bottom edge from the bottom of the
    /// screen. The panel itself sits lower because PillView adds 36pt of
    /// bottom padding for shadow room; we subtract that when placing the
    /// panel so the visible pill lands here regardless of padding changes.
    private static let bottomMargin: CGFloat = 80
    /// Bottom inset inside PillView (panel origin → visible pill bottom).
    /// Must mirror the bottom padding in PillView.body.
    private static let pillBottomInset: CGFloat = 48
    /// Distance in points within which the pill softly snaps to a guide.
    /// Larger value = "stickier" snap. 28 makes the centre-line feel magnetic.
    private static let snapThreshold: CGFloat = 28
    /// Persists the user's last manual position per-display.
    private static let positionKey = "PillWindow.lastOriginByScreen"

    private var panel: PillPanel?
    private let viewModel = PillViewModel()

    init() {
        // Re-arm the spawn after every model switch. PreferencesStore posts
        // .activeModelDidChange in its activeModelID didSet (after dedup).
        // Scope to PreferencesStore.shared so we don't re-arm spawn from
        // any unrelated notification post (defensive against future code
        // paths that might post .activeModelDidChange for other reasons).
        modelChangeObserver = NotificationCenter.default.addObserver(
            forName: .activeModelDidChange,
            object: PreferencesStore.shared,
            queue: .main
        ) { [weak self] _ in
            self?.spawnPending = true
        }
    }

    deinit {
        if let observer = modelChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Fired when the cinematic spawn animation finishes (i.e. when the pill
    /// has transitioned from `.spawning(...)` to `.armed`). AppCoordinator
    /// registers a closure here to drain its audio buffer + start streaming.
    /// On a non-spawn `show()` (subsequent presses in the same session), this
    /// fires synchronously inside `show()` so the same code path always works.
    var onSpawnComplete: (() -> Void)?

    /// Fired when the install **intro** animation finishes — i.e. the pill
    /// has just transitioned from `.installSpawning(...)` to
    /// `.installCompiling(progress: 0)`. AppCoordinator wires this up to
    /// start driving rim progress (`setInstallProgress(_:)`) from the actual
    /// model warm-up state.
    ///
    /// Distinct from `onSpawnComplete` because the install path doesn't
    /// drain audio at this point — audio capture hasn't started yet on a
    /// fresh-install hotkey press; it begins once the outro completes and
    /// the pill is in `.armed`.
    var onInstallIntroComplete: (() -> Void)?

    /// Fired when the install **outro** animation finishes — pill has just
    /// transitioned to `.armed`. AppCoordinator uses this as the cue to
    /// start audio capture and streaming, the same way it would after
    /// `onSpawnComplete` fires for the cinematic spawn path.
    var onInstallOutroComplete: (() -> Void)?

    /// **For tests only.** Production code should never read the view model
    /// directly — go through `setPhase`, `updateLevel`, etc.
    var viewModelForTesting: PillViewModel { viewModel }

    func show() {
        // Defensive: if a previous spawn (cinematic OR install) is still
        // running, cancel it cleanly so it doesn't overwrite the .armed
        // phase below. show() is normally paired with hide() by the hotkey
        // lifecycle, but double-press or other races can hit this — and a
        // mid-install hotkey release on a different display would too.
        viewModel.cancelSpawn()
        viewModel.cancelInstall()

        // Set the phase to the correct first frame BEFORE the panel becomes
        // visible. Same flash-prevention rationale as showInstall(): without
        // this, SwiftUI renders one frame at the previous phase (typically
        // .idle from a freshly-created panel) before the spawn Task fires
        // and updates the phase. See showInstall() for the full explanation.
        if spawnPending {
            viewModel.phase = .spawning(progress: 0)
        } else {
            viewModel.phase = .armed
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(targetOrigin(for: panel))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
        }

        if spawnPending {
            spawnPending = false
            Task { @MainActor [weak self] in
                guard let self else { return }
                let completed = await self.viewModel.playSpawn()
                if completed {
                    self.onSpawnComplete?()
                }
            }
        } else {
            // Phase already set to .armed above; just dispatch the callback
            // async (matching the cinematic path) so AppCoordinator's
            // callback can't re-enter PillWindowController synchronously
            // inside show(). Both paths now have the same re-entrancy
            // behaviour.
            let cb = onSpawnComplete
            Task { @MainActor in cb?() }
        }
    }

    /// Install-animation entry point. Called by AppCoordinator when the user
    /// presses the hotkey while the model is still warming up
    /// (`state == .loadingModel`). Plays the install intro animation, then
    /// fires `onInstallIntroComplete` so the coordinator can start driving
    /// `setInstallProgress(_:)` from the actual warm-up state.
    ///
    /// Does NOT consume the `spawnPending` flag — install and spawn are
    /// distinct entry points. After the install outro completes, the next
    /// press of the hotkey will play either a cinematic spawn (if pending)
    /// or instant `.armed`, whichever the spawn-pending machinery dictates.
    func showInstall() {
        // Defensive cancels — same rationale as show(): we might be hitting
        // this during a previous in-flight install (rapid model switch,
        // recovery from an error path) or a previous cinematic spawn.
        viewModel.cancelSpawn()
        viewModel.cancelInstall()

        // CRITICAL: set the phase to the install intro's first frame BEFORE
        // the panel becomes visible. Without this, the panel briefly renders
        // at the previous .idle phase (full 170pt pill with figures + bars)
        // before the playInstallSpawn Task gets scheduled and flips the
        // phase to .installSpawning(progress: 0) (63pt seed pill, figures
        // invisible). The user sees a "full pill snaps small, then expands"
        // ugly flash before the actual install choreography begins.
        // Setting phase synchronously here means SwiftUI's first render of
        // the panel after orderFrontRegardless is already at the seed-pill
        // state — the very first frame the user sees.
        viewModel.phase = .installSpawning(progress: 0)

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(targetOrigin(for: panel))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            // playInstallSpawn re-sets phase = .installSpawning(progress: 0)
            // and then drives it to 1.0 over `duration`. The redundant
            // re-set is harmless — SwiftUI dedupes Equatable @Published
            // changes, and the timeline always starts at 0 anyway.
            let completed = await self.viewModel.playInstallSpawn()
            // playInstallSpawn ends with phase = .installCompiling(progress: 0).
            // Fire the callback only on uncancelled completion so the
            // coordinator doesn't start driving progress on a pill that
            // already moved on (e.g. early hotkey release).
            if completed {
                self.onInstallIntroComplete?()
            }
        }
    }

    /// Push a new rim-progress value from the warm-up driver. Caller is
    /// expected to clamp to `[0, 1]`; the underlying view model also clamps
    /// defensively. No-op if the pill isn't currently in
    /// `.installCompiling`, so out-of-band calls (e.g. progress arriving
    /// after the user already released the hotkey and we ran the outro) are
    /// silently ignored.
    func setInstallProgress(_ p: Double) {
        viewModel.setInstallProgress(p)
    }

    /// Play the install outro animation (rim fade + label fade + circle
    /// traverse + bar cascade + comet ignite) and transition to `.armed`.
    /// Fires `onInstallOutroComplete` on completion. Caller is expected to
    /// have first set rim progress to 1.0 via `setInstallProgress(1.0)` so
    /// the rim is visually full when the outro begins fading it out.
    func playInstallOutro() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let completed = await self.viewModel.playInstallOutro()
            if completed {
                self.onInstallOutroComplete?()
            }
        }
    }

    /// Spec calls for the pill to scale slightly down (1.0 → 0.97) and fade
    /// out on completion. We do that here on the panel's contentView via a
    /// CALayer transform in addition to fading alpha.
    func hide() {
        guard let panel else { return }
        viewModel.cancelSpawn()    // safe no-op if no spawn in flight
        viewModel.cancelInstall()  // ditto for install intro / outro
        viewModel.phase = .idle
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.viewModel.level = 0
        })
    }

    func updateLevel(_ level: Float) {
        viewModel.level = level
        // Auto-promote .armed → .listening when audio rises above a tiny gate,
        // and demote back when it falls. Threshold tuned by ear: 0.05 RMS is
        // roughly "background room noise + speech onset," low enough to fire
        // promptly but not so low that a fan triggers it.
        if viewModel.phase == .armed && level > 0.05 {
            viewModel.phase = .listening
        } else if viewModel.phase == .listening && level < 0.02 {
            viewModel.phase = .armed
        }
    }

    /// Used by AppCoordinator to drive the pill into the .processing phase
    /// (hotkey released, transcription finalising).
    func setPhase(_ phase: PillPhase) {
        viewModel.phase = phase
    }

    private func makePanel() -> PillPanel {
        let frame = NSRect(origin: .zero, size: Self.pillSize)
        let panel = PillPanel(contentRect: frame)
        let host = NSHostingView(rootView: PillView(viewModel: viewModel))
        host.frame = frame
        host.autoresizingMask = [.width, .height]
        // Make the SwiftUI host fully transparent — without this, NSHostingView
        // on macOS 15+ paints a subtle rounded "liquid glass" backdrop behind
        // the entire view's bounds, which read as a half-transparent box around
        // our pill.
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = makeContainer(host: host)
        panel.delegate = panelDelegate
        return panel
    }

    private func makeContainer(host: NSHostingView<PillView>) -> NSView {
        let container = DraggablePillView(frame: NSRect(origin: .zero, size: Self.pillSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        // Real-time soft-snap: while dragging, route every candidate position
        // through `snap()`. When the candidate is within `snapThreshold` of the
        // centre line or the default bottom line, the panel locks onto the
        // guide. This is what makes the snap feel magnetic instead of "I drop
        // it and it teleports a little."
        container.snapTransform = { [weak self] candidate in
            guard let self, let panel = self.panel else { return candidate }
            let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first!
            return self.snap(origin: candidate, on: screen, panelSize: panel.frame.size)
        }
        container.onDragEnded = { [weak self] in self?.snapAndPersist() }
        container.addSubview(host)
        return container
    }

    private lazy var panelDelegate = PanelDelegate()

    // MARK: - Positioning

    private func targetOrigin(for panel: NSPanel) -> NSPoint {
        let screen = focusedScreen() ?? NSScreen.main ?? NSScreen.screens.first!
        if let saved = savedOrigin(for: screen) {
            return clamped(saved, into: screen.visibleFrame, panelSize: panel.frame.size)
        }
        return defaultOrigin(on: screen, panelSize: panel.frame.size)
    }

    private func defaultOrigin(on screen: NSScreen, panelSize: NSSize) -> NSPoint {
        let frame = screen.visibleFrame
        return NSPoint(
            x: frame.midX - panelSize.width / 2,
            // Place the panel so the *visible pill* (inset 36pt above the
            // panel's bottom edge for shadow room) sits at bottomMargin.
            y: frame.minY + Self.bottomMargin - Self.pillBottomInset
        )
    }

    private func snapAndPersist() {
        guard let panel else { return }
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let snapped = snap(origin: panel.frame.origin, on: screen, panelSize: panel.frame.size)
        if snapped != panel.frame.origin {
            panel.animator().setFrameOrigin(snapped)
        }
        persistOrigin(snapped, for: screen)
    }

    /// Soft-snap to the vertical centre line and to the default bottom horizontal line.
    private func snap(origin: NSPoint, on screen: NSScreen, panelSize: NSSize) -> NSPoint {
        let frame = screen.visibleFrame
        var x = origin.x
        var y = origin.y

        let centreX = frame.midX - panelSize.width / 2
        if abs(x - centreX) < Self.snapThreshold {
            x = centreX
        }

        let bottomY = frame.minY + Self.bottomMargin - Self.pillBottomInset
        if abs(y - bottomY) < Self.snapThreshold {
            y = bottomY
        }

        return clamped(NSPoint(x: x, y: y), into: frame, panelSize: panelSize)
    }

    private func clamped(_ point: NSPoint, into frame: NSRect, panelSize: NSSize) -> NSPoint {
        let x = min(max(point.x, frame.minX), frame.maxX - panelSize.width)
        let y = min(max(point.y, frame.minY), frame.maxY - panelSize.height)
        return NSPoint(x: x, y: y)
    }

    private func focusedScreen() -> NSScreen? {
        // Mouse position is a reliable proxy for "the display the user is currently working on".
        // Querying AX for the focused window's frame is heavier and not needed here.
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    // MARK: - Persistence

    private func screenKey(_ screen: NSScreen) -> String {
        let nsNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return nsNumber.map { "\($0.uint32Value)" } ?? "default"
    }

    private func savedOrigin(for screen: NSScreen) -> NSPoint? {
        let dict = UserDefaults.standard.dictionary(forKey: Self.positionKey) ?? [:]
        guard let raw = dict[screenKey(screen)] as? [String: CGFloat],
              let x = raw["x"], let y = raw["y"] else { return nil }
        return NSPoint(x: x, y: y)
    }

    private func persistOrigin(_ point: NSPoint, for screen: NSScreen) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.positionKey) ?? [:]
        dict[screenKey(screen)] = ["x": point.x, "y": point.y]
        UserDefaults.standard.set(dict, forKey: Self.positionKey)
    }
}

/// NSView subclass that lets the user drag the pill around like the macOS
/// Spotlight bar. Optionally pipes each candidate origin through `snapTransform`
/// for real-time soft-snapping during drag.
private final class DraggablePillView: NSView {
    /// Called once when the user releases the mouse (for persistence).
    var onDragEnded: (() -> Void)?
    /// Called for every drag tick; can return a snapped origin.
    var snapTransform: ((NSPoint) -> NSPoint)?

    private var dragOriginInWindow: NSPoint?

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let mouseInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        dragOriginInWindow = mouseInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let origin = dragOriginInWindow else { return }
        let mouseScreen = NSEvent.mouseLocation
        let candidate = NSPoint(
            x: mouseScreen.x - origin.x,
            y: mouseScreen.y - origin.y
        )
        let target = snapTransform?(candidate) ?? candidate
        window.setFrameOrigin(target)
    }

    override func mouseUp(with event: NSEvent) {
        dragOriginInWindow = nil
        onDragEnded?()
    }
}

private final class PanelDelegate: NSObject, NSWindowDelegate {}
