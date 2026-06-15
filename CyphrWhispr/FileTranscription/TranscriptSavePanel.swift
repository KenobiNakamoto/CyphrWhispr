import AppKit

/// Builds and runs the result window's "Save as…" panel with a format
/// chooser, then writes the chosen format to the chosen URL.
///
/// Uses a custom accessory popup rather than `NSSavePanel`'s built-in File
/// Format popup because two of our formats — plain text and timestamped
/// text — share the `.txt` extension. The built-in popup keys off
/// UTType/extension, so it can't present two distinct `.txt` choices; our
/// popup drives the format selection directly and we set the filename
/// extension ourselves.
///
/// Lives for exactly one modal run: created, `.run()` blocks on
/// `runModal()`, then released. The popup's `target = self` is safe because
/// `self` outlives the synchronous modal.
@MainActor
final class TranscriptSavePanel: NSObject {
    private let transcript: FileTranscript
    private let panel = NSSavePanel()
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formats = TranscriptExportFormat.allCases

    init(transcript: FileTranscript) {
        self.transcript = transcript
        super.init()
        build()
    }

    private func build() {
        panel.title = "Save Transcript"
        panel.canCreateDirectories = true
        panel.directoryURL = transcript.sourceURL.deletingLastPathComponent()

        popup.addItems(withTitles: formats.map(\.menuTitle))
        popup.target = self
        popup.action = #selector(formatChanged)
        popup.sizeToFit()

        let label = NSTextField(labelWithString: "Format:")

        // NSStackView computes its own fitting size, which NSSavePanel honours
        // when laying out the accessory band — no manual frame math needed.
        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        panel.accessoryView = stack

        updateFilename()  // seed the name field with the default format's extension
    }

    /// The format the popup currently points at. `indexOfSelectedItem` is -1
    /// only before any item exists; we add items in `build()` so it's always
    /// valid here, but clamp defensively.
    private var selectedFormat: TranscriptExportFormat {
        formats[max(0, min(popup.indexOfSelectedItem, formats.count - 1))]
    }

    @objc private func formatChanged() {
        updateFilename()
    }

    /// Keep the save panel's filename extension in sync with the selected
    /// format, preserving whatever base name the user has typed.
    private func updateFilename() {
        let current = panel.nameFieldStringValue
        let base = current.isEmpty
            ? transcript.sourceURL.deletingPathExtension().lastPathComponent
            : (current as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + "." + selectedFormat.fileExtension
    }

    /// Present the modal, render the chosen format, and write it. Surfaces a
    /// warning alert on write failure — same behaviour the inline save code
    /// had before this controller existed. No-op if the user cancels.
    func run() {
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let body = selectedFormat.render(transcript)
        do {
            try body.write(to: dest, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't save transcript"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
