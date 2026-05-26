import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings tab dedicated to ad-hoc file transcription.
///
/// Three sections:
///   1. A big drop zone — accepts drag-and-drop of audio/video files, and
///      doubles as a click-to-browse button that opens an `NSOpenPanel`.
///   2. A read-only "Defaults" card that surfaces which model + language
///      will be used for new transcriptions. The active values come straight
///      from `PreferencesStore` (same as live dictation) so changing one
///      surface flows to the other.
///   3. A "Recent" card listing the last ~10 file transcriptions, with each
///      row's outcome rendered as a CWToken. "Reopen" pops a fresh result
///      window for the same source file; "Clear all" wipes the list.
///
/// All three result-window entry points (drag, click, reopen) end at
/// `TranscriptResultWindowController.shared.showNewWindow(for:)`, which is
/// also what the menu bar / URL scheme / Finder Sync extension use.
struct TranscribeTabView: View {
    @EnvironmentObject private var prefs: PreferencesStore
    @ObservedObject private var recents = RecentTranscriptionsStore.shared

    @State private var isTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead3(
                    title: "Transcribe",
                    subtitle: "Drop or pick any audio or video file to get a clean transcript back. "
                            + "Export as .txt, .srt, or .vtt."
                )

                dropZone
                    .padding(.bottom, CWSpace.s5)

                Card3(title: "Defaults") {
                    Row3(label: "Model",
                         sub: "Set on the Models tab. Used for new file transcripts.") {
                        Text(activeModelDisplayName)
                            .font(CWFont.mono(size: CWFont.s12, weight: .medium))
                            .foregroundColor(.cwFg2)
                    }
                    Row3(label: "Language",
                         sub: "Set on the General tab.",
                         isLast: true) {
                        Text(activeLanguageDisplayName)
                            .font(CWFont.mono(size: CWFont.s12, weight: .medium))
                            .foregroundColor(.cwFg2)
                    }
                }

                if !recents.entries.isEmpty {
                    recentsCard
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        Button(action: openFilePicker) {
            VStack(spacing: 10) {
                Text("↓")
                    .font(CWFont.mono(size: 36, weight: .semibold))
                    .foregroundColor(isTargeted ? prefs.accent : .cwFg2)
                Text(isTargeted ? "Release to transcribe" : "Drop an audio or video file")
                    .font(CWFont.mono(size: CWFont.s13, weight: .medium))
                    .foregroundColor(.cwFg1)
                Text("or click to browse")
                    .font(CWFont.mono(size: CWFont.s11, weight: .regular))
                    .foregroundColor(.cwFg3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background(
                ZStack {
                    Color.cwSurface1.opacity(isTargeted ? 0.55 : 0.30)
                    if isTargeted {
                        prefs.accent.opacity(0.08)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: CWRadius.lg)
                    .strokeBorder(
                        isTargeted ? prefs.accent : .cwBorderStrong,
                        style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: CWRadius.lg))
            .shadow(color: isTargeted ? prefs.accent.opacity(0.35) : .clear,
                    radius: 16, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    /// Read the first dropped item provider, pull a file URL out, and open a
    /// result window if the file is audio/video. SwiftUI's `.onDrop` callback
    /// runs off the main thread inside `loadDataRepresentation`, so the
    /// `showNewWindow` call hops back to `@MainActor`.
    @discardableResult
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier
        ) { data, _ in
            guard let data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  Self.isMediaFile(url) else { return }
            Task { @MainActor in
                TranscriptResultWindowController.shared.showNewWindow(for: url)
            }
        }
        return true
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Transcribe File"
        panel.prompt = "Transcribe"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        TranscriptResultWindowController.shared.showNewWindow(for: url)
    }

    private static func isMediaFile(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        else { return false }
        return type.conforms(to: .audio)
            || type.conforms(to: .movie)
            || type.conforms(to: .audiovisualContent)
    }

    // MARK: - Defaults

    /// Resolve the active model's friendly name from the catalog. Falls back
    /// to the raw model ID if the catalog doesn't list it (rare — only happens
    /// when the user pasted a custom model ID directly into preferences).
    private var activeModelDisplayName: String {
        ModelCatalog.all.first(where: { $0.id == prefs.activeModelID })?.displayName
            ?? prefs.activeModelID
    }

    private var activeLanguageDisplayName: String {
        if let lang = TranscriptionLanguageCatalog.language(for: prefs.selectedLanguageCode) {
            if let native = lang.nativeName {
                return "\(lang.displayName) — \(native)"
            }
            return lang.displayName
        }
        return prefs.selectedLanguageCode
    }

    // MARK: - Recents

    private var recentsCard: some View {
        Card3(title: "Recent", meta: "\(recents.entries.count)") {
            ForEach(Array(recents.entries.enumerated()), id: \.element.id) { idx, entry in
                Row3(label: entry.filename,
                     sub: entryDetailText(entry),
                     isLast: idx == recents.entries.count - 1) {
                    HStack(spacing: 8) {
                        statusToken(for: entry.outcome)
                        CWButton(title: "Reopen",
                                 variant: .ghost,
                                 indicator: .glyph("↻")) {
                            TranscriptResultWindowController.shared.showNewWindow(for: entry.sourceURL)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                CWButton(title: "Clear all", variant: .ghost) {
                    recents.clearAll()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(Rectangle().fill(Color.cwBorder).frame(height: 1), alignment: .top)
        }
    }

    @ViewBuilder
    private func statusToken(for outcome: RecentTranscriptionsStore.Outcome) -> some View {
        switch outcome {
        case .done:
            CWToken(text: "done", variant: .downloaded, indicator: .glyph("✓"), size: .sm)
        case .failed:
            CWToken(text: "failed", variant: .missing, indicator: .glyph("!"), size: .sm)
        }
    }

    /// `5 min ago · 428 words · 21:34` for done entries, or
    /// `5 min ago · failed` for failures. RelativeDateTimeFormatter handles
    /// the localised "5 min ago" / "yesterday" / "2 days ago" wording.
    private func entryDetailText(_ entry: RecentTranscriptionsStore.Entry) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let timeAgo = formatter.localizedString(for: entry.timestamp, relativeTo: Date())
        switch entry.outcome {
        case .done(let words, let duration):
            return "\(timeAgo) · \(words) words · \(Self.compactDuration(duration))"
        case .failed:
            return "\(timeAgo) · failed"
        }
    }

    /// `21:34` (m:ss) or `1:02:15` (h:mm:ss) — same compact recipe the result
    /// window header uses so the two surfaces read consistently.
    private static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total / 60) % 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    TranscribeTabView()
        .environmentObject(PreferencesStore.shared)
        .frame(width: 720, height: 700)
        .preferredColorScheme(.dark)
}
