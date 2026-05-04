import AppKit

/// Captures the full state of `NSPasteboard.general` so we can restore it after
/// hijacking the clipboard for a synthetic ⌘V paste.
///
/// Naive `pasteboard.string = ...; pasteboard.string = saved` destroys images,
/// file URLs, RTF, and Universal Clipboard handoff. We capture every
/// `NSPasteboardItem` with all its types and re-emit them on restore.
///
/// We also tag our temporary write with the well-known nspasteboard.org
/// "transient" and "concealed" UTIs. Clipboard-history apps (Raycast, Alfred,
/// Paste, Copy 'Em) respect these and won't archive the transcription.
struct PasteboardSnapshot {
    private let items: [Snapshot]
    private let changeCount: Int

    private struct Snapshot {
        let payloads: [NSPasteboard.PasteboardType: Data]
    }

    static let transientUTI = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedUTI = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let snapshots = (pasteboard.pasteboardItems ?? []).map { item -> Snapshot in
            var payloads: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    payloads[type] = data
                }
            }
            return Snapshot(payloads: payloads)
        }
        return PasteboardSnapshot(items: snapshots, changeCount: pasteboard.changeCount)
    }

    /// Write a transcription to the pasteboard, marked transient + concealed so
    /// clipboard managers ignore it.
    static func writeTranscription(
        _ text: String,
        to pasteboard: NSPasteboard = .general
    ) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Empty-string markers are the convention nspasteboard.org documents.
        item.setString("", forType: transientUTI)
        item.setString("", forType: concealedUTI)
        pasteboard.writeObjects([item])
    }

    /// Restore the captured state. Caller is responsible for waiting long
    /// enough after their synthetic ⌘V that the receiving app has actually
    /// read from the pasteboard.
    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let restored: [NSPasteboardItem] = items.map { snap in
            let item = NSPasteboardItem()
            for (type, data) in snap.payloads {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
