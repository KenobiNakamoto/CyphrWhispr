import AppKit
import UniformTypeIdentifiers
import KeyboardShortcuts  // .toggleDictation name + getShortcut for menu header

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    var onQuit: (() -> Void)?

    /// Fires when the user picks "Transcribe File…" from the menu, or drops
    /// a media file directly onto the status item glyph.
    ///
    /// - `nil`  → the user picked the menu item, so the host should present
    ///            an `NSOpenPanel` filtered to audio/video.
    /// - `URL`  → a media file the user dragged onto the icon; pass it
    ///            straight to `TranscriptResultWindowController.showNewWindow(for:)`.
    var onTranscribeFile: ((URL?) -> Void)?

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
            installFileDropOverlay(on: button)
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

    // MARK: - Menu construction
    //
    // The menu is rebuilt on every open via the NSMenuDelegate callback
    // (`menuNeedsUpdate`) so that dynamic state stays fresh without us
    // wiring per-property observers: the shortcut display reflects any
    // rebind the user just made in Settings, the activation-mode
    // checkmark mirrors whatever `prefs.activationMode` is RIGHT NOW,
    // the model submenu only lists models that are still on disk, and
    // the "Last transcription" preview reflects the most recent commit.
    // Rebuilding ~once per click of the menubar icon is essentially free
    // and dodges a whole class of "stale checkmark / stale entry" bugs.
    //
    // Stable structure (most → least frequent interaction):
    //   1. Hotkey + activation mode (top — answers "how do I use this?")
    //   2. Last transcription (preview + Copy)
    //   3. Model + switcher
    //   4. History / Transcribe / Settings (windowed surfaces)
    //   5. Quit

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false  // we set `isEnabled` explicitly per item
        menu.delegate = self
        // Build once so the menu is populated even if `menuNeedsUpdate`
        // doesn't fire on initial install (e.g. AppKit only calls it on
        // user-initiated opens). Subsequent opens replace the contents.
        rebuildMenuItems(into: menu)
        return menu
    }

    /// NSMenuDelegate hook — fires immediately before the menu becomes
    /// visible each time the user clicks the status item. We always
    /// regenerate the full item list rather than diffing because the data
    /// shape (checkmarks across two submenus, a variable-length model
    /// list, a Copy item that may or may not exist) makes incremental
    /// updates more error-prone than it's worth. Rebuilding ~once per
    /// click is imperceptible.
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        // The delegate method itself is nonisolated (per the AppKit
        // protocol), so hop to the main actor to touch our state.
        MainActor.assumeIsolated {
            rebuildMenuItems(into: menu)
        }
    }

    private func rebuildMenuItems(into menu: NSMenu) {
        menu.removeAllItems()

        // No "CyphrWhispr" title row — the status-bar glyph is already the
        // brand affordance and the menu shouldn't waste its first slot on
        // restating what the user clicked to open it.

        // --- Section 1: hotkey + activation mode -----------------------
        addHotkeySection(to: menu)
        menu.addItem(.separator())

        // --- Section 2: last transcription preview + Copy --------------
        addLastTranscriptSection(to: menu)
        menu.addItem(.separator())

        // --- Section 3: model + switcher submenu -----------------------
        addModelSection(to: menu)
        menu.addItem(.separator())

        // --- Section 4: windowed surfaces ------------------------------
        let historyItem = NSMenuItem(
            title: "History…",
            action: #selector(historyTapped),
            keyEquivalent: ""
        )
        historyItem.target = self
        menu.addItem(historyItem)

        let transcribeItem = NSMenuItem(
            title: "Transcribe File…",
            action: #selector(transcribeFileTapped),
            keyEquivalent: "o"
        )
        // ⌘O is only active while the menu is open — not a global hotkey —
        // but it makes the keyboard path obvious to power users.
        transcribeItem.target = self
        menu.addItem(transcribeItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(settingsTapped),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // --- Section 5: Quit -------------------------------------------
        let quitItem = NSMenuItem(
            title: "Quit CyphrWhispr",
            action: #selector(quitTapped),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: Section 1 — hotkey + activation mode
    //
    // Two clickable rows, no submenu — the menu's already short and a
    // submenu for a 2-state toggle is more friction than the toggle saves.
    //
    //   • Shortcut row  — title is the live shortcut ("⌥Space"). Click
    //     opens Settings → Shortcut, where the KeyboardShortcuts recorder
    //     handles the actual rebind.
    //   • Mode row      — title is the current activation mode label.
    //     Click flips it to the other mode in place; the next hotkey
    //     press picks up the new mode (`HotkeyManager` re-wires on
    //     `.activationModeDidChange`).
    //
    // Both rows carry tooltips that explain the action; the menu itself
    // shows the *state*, not "Click to change…" verbosity.

    private func addHotkeySection(to menu: NSMenu) {
        // Shortcut row — display + jump-to-Settings.
        let shortcutItem = NSMenuItem(
            title: currentShortcutDescription(),
            action: #selector(openShortcutSettings),
            keyEquivalent: ""
        )
        shortcutItem.target = self
        shortcutItem.toolTip = "Click to change the dictation shortcut"
        menu.addItem(shortcutItem)

        // Mode toggle row — clicking flips between push-to-talk and toggle.
        let currentMode = PreferencesStore.shared.activationMode
        let otherMode: PreferencesStore.ActivationMode =
            (currentMode == .pushToTalk) ? .toggle : .pushToTalk
        let modeItem = NSMenuItem(
            title: currentMode.menuLabel,
            action: #selector(toggleActivationMode),
            keyEquivalent: ""
        )
        modeItem.target = self
        modeItem.toolTip = "Click to switch to \(otherMode.menuLabel)"
        menu.addItem(modeItem)
    }

    /// "⌥Space" / "⌃⌘C" / "No shortcut bound". Pulls from
    /// `KeyboardShortcuts.getShortcut(for:)`, which is updated by the
    /// rebind recorder in Settings and persisted via the library's own
    /// UserDefaults backing.
    private func currentShortcutDescription() -> String {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleDictation) {
            return shortcut.description
        }
        return "No shortcut bound"
    }

    // MARK: Section 2 — last transcription
    //
    // Single-row action — the verbatim transcript stays out of the menu
    // entirely. Showing the text inline made the menu feel like a
    // history surface (which History tab already is) and could surface
    // sensitive content over the user's shoulder; the menu's role here
    // is just "copy what I just dictated again".

    private func addLastTranscriptSection(to menu: NSMenu) {
        let hasTranscript = LastTranscriptStore.shared.lastTranscript != nil
        let item = NSMenuItem(
            title: hasTranscript ? "Copy last transcription" : "No recent transcription",
            action: hasTranscript ? #selector(copyLastTranscriptTapped) : nil,
            keyEquivalent: hasTranscript ? "c" : ""
        )
        item.target = hasTranscript ? self : nil
        item.isEnabled = hasTranscript
        if hasTranscript {
            item.toolTip = "Copy the last dictated text to the clipboard"
        }
        menu.addItem(item)
    }

    // MARK: Section 3 — model + switcher submenu

    private func addModelSection(to menu: NSMenu) {
        let activeID = PreferencesStore.shared.activeModelID
        let activeName = ModelCatalog.model(id: activeID)?.displayName ?? activeID
        let header = NSMenuItem(title: "Model: \(activeName)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let switcherItem = NSMenuItem(title: "Switch model", action: nil, keyEquivalent: "")
        let switcherSubmenu = NSMenu(title: "Switch model")
        switcherSubmenu.autoenablesItems = false

        let downloaded = AppSupportPaths.downloadedModelIDs()
        if downloaded.isEmpty {
            let none = NSMenuItem(title: "No models installed", action: nil, keyEquivalent: "")
            none.isEnabled = false
            switcherSubmenu.addItem(none)
        } else {
            // Stable display order: catalog order first (matches the
            // Settings → Models list), then any custom/imported models
            // alphabetically at the bottom. The user's mental model
            // — "the order I see in Settings" — should match here.
            let catalogIDs = ModelCatalog.all.map(\.id)
            let orderedDownloaded: [String] =
                catalogIDs.filter { downloaded.contains($0) }
                + downloaded.subtracting(catalogIDs).sorted()

            for id in orderedDownloaded {
                let display = ModelCatalog.model(id: id)?.displayName ?? id
                let item = NSMenuItem(
                    title: display,
                    action: #selector(modelPicked(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = id
                item.state = (id == activeID) ? .on : .off
                switcherSubmenu.addItem(item)
            }
        }
        switcherSubmenu.addItem(.separator())
        let manageItem = NSMenuItem(
            title: "Manage models…",
            action: #selector(openModelsSettings),
            keyEquivalent: ""
        )
        manageItem.target = self
        switcherSubmenu.addItem(manageItem)

        switcherItem.submenu = switcherSubmenu
        menu.addItem(switcherItem)
    }

    // MARK: - Action handlers

    @objc private func quitTapped() {
        onQuit?()
    }

    /// Open Settings via our manually-managed window controller.
    /// (We don't use SwiftUI's `Settings` scene + `showSettingsWindow:` action
    /// because it's flaky in accessory-activation apps with no key window.)
    @objc private func settingsTapped() {
        SettingsWindowController.shared.show()
    }

    /// Menu-item handler. Passes `nil` so the host presents an open panel —
    /// drag-onto-icon hits `onTranscribeFile` with the dragged URL instead.
    @objc private func transcribeFileTapped() {
        onTranscribeFile?(nil)
    }

    /// Pre-select the History tab via UserDefaults, then surface the
    /// Settings window. `@AppStorage("cw.settings.tab")` inside SettingsView
    /// observes UserDefaults, so the write before `.show()` takes effect
    /// on the next view evaluation — including when the window is already
    /// open and we're just bringing it forward.
    @objc private func historyTapped() {
        UserDefaults.standard.set(
            "History",
            forKey: "cw.settings.tab"
        )
        SettingsWindowController.shared.show()
    }

    /// Same pattern as `historyTapped` but for the Shortcut tab — the menu's
    /// "Change shortcut…" leaf inside the Activation submenu lands here.
    @objc private func openShortcutSettings() {
        UserDefaults.standard.set(
            "Shortcut",
            forKey: "cw.settings.tab"
        )
        SettingsWindowController.shared.show()
    }

    /// Same pattern but for the Models tab — the model switcher submenu's
    /// "Manage models…" tail lands here.
    @objc private func openModelsSettings() {
        UserDefaults.standard.set(
            "Models",
            forKey: "cw.settings.tab"
        )
        SettingsWindowController.shared.show()
    }

    @objc private func copyLastTranscriptTapped() {
        LastTranscriptStore.shared.copyToPasteboard()
    }

    /// Flip the activation mode from push-to-talk to toggle (or back).
    /// Writing to `prefs.activationMode` posts `.activationModeDidChange`,
    /// which `HotkeyManager` already observes — the mode swap takes effect
    /// on the very next hotkey press, with no app restart needed.
    @objc private func toggleActivationMode() {
        let prefs = PreferencesStore.shared
        prefs.activationMode = (prefs.activationMode == .pushToTalk) ? .toggle : .pushToTalk
    }

    /// Model picker items carry the variant ID in `representedObject`.
    /// Writing to `prefs.activeModelID` flows through the existing Combine
    /// sink in `AppCoordinator.start()`, which triggers `switchModel(to:)`
    /// — same path the Settings → Models tab uses, so the menu pick
    /// gets the same hot-swap behaviour (cancels mid-session if recording,
    /// shows the loading-model state in the menu bar, etc.).
    @objc private func modelPicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        PreferencesStore.shared.activeModelID = id
    }

    // MARK: - Drag-and-drop on the menu bar glyph
    //
    // The status item's button is an `NSStatusBarButton` we don't own and
    // can't subclass cleanly. We get drop support by overlaying a
    // transparent `NSView` that registers for file URL drags. `hitTest`
    // returns nil on the overlay so mouse clicks still reach the underlying
    // button (and its menu still opens). Drag events use a separate
    // dispatch path that doesn't consult `hitTest`, so file drops land on
    // the overlay.

    private func installFileDropOverlay(on button: NSStatusBarButton) {
        // Idempotent — if a previous overlay survived, leave it alone.
        if button.subviews.contains(where: { $0 is FileDropOverlayView }) { return }
        let overlay = FileDropOverlayView(frame: button.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onAcceptedDrop = { [weak self] url in
            self?.onTranscribeFile?(url)
        }
        button.addSubview(overlay)
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

// MARK: - File drop overlay

/// Transparent overlay subview that turns the menu-bar glyph into a drop
/// target for audio/video files. Filters dragged URLs via UTType so the
/// drop visually rejects non-media files (no `.copy` cursor badge appears
/// while dragging a random text file over the icon).
private final class FileDropOverlayView: NSView {
    /// Called once with the accepted file URL when a media-conforming file
    /// is dropped on the menu bar glyph.
    var onAcceptedDrop: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { nil }

    /// Returning nil lets mouse clicks fall through to the underlying
    /// `NSStatusBarButton`, so the menu still opens normally. Drag-and-
    /// drop events use a separate dispatch path that doesn't consult
    /// `hitTest`, so the overlay still receives them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.firstAcceptableURL(from: sender) != nil ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.firstAcceptableURL(from: sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = Self.firstAcceptableURL(from: sender) else { return false }
        onAcceptedDrop?(url)
        return true
    }

    /// First audio/video URL on the dragging pasteboard, or nil if the
    /// drag carries no acceptable file. Dragging several files at once
    /// transcribes the first media file; non-media siblings are ignored.
    /// (Multi-file batching is a v2 concern — for now a single window per
    /// drop matches the "ad-hoc" framing.)
    private static func firstAcceptableURL(from sender: NSDraggingInfo) -> URL? {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: NSNumber(value: true)]
        ) as? [URL] ?? []
        return urls.first(where: { isMediaFile($0) })
    }

    private static func isMediaFile(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        // `.audio` covers mp3/m4a/wav/aiff/flac; `.movie` covers mp4/mov/m4v;
        // `.audiovisualContent` is the umbrella so we accept exotic
        // containers AVFoundation supports (e.g. caf, 3gp).
        return type.conforms(to: .audio)
            || type.conforms(to: .movie)
            || type.conforms(to: .audiovisualContent)
    }
}
