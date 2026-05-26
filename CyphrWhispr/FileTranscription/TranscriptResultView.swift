import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Content for the file-transcription result window. Driven by a single
/// `FileTranscriptionService` bound at construction. Lifecycle is owned by
/// the window controller, not the view — the view re-renders against the
/// service's `@Published var status` and surfaces three states:
///
///   • `.idle` / `.decoding` / `.transcribing` — status pill + a determinate
///     bar (decode) or indeterminate spinner (transcribe).
///   • `.done(transcript)` — scrollable monospaced transcript with Copy +
///     Save as… buttons in the footer.
///   • `.failed(message)` — danger-tinted message card.
///
/// Save as… surfaces an `NSSavePanel` with `.txt / .srt / .vtt` content types
/// — the user picks the format from the save panel's built-in type popup,
/// and we write the matching exporter output to the chosen URL.
struct TranscriptResultView: View {
    @ObservedObject var service: FileTranscriptionService
    @EnvironmentObject private var prefs: PreferencesStore

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                Rectangle().fill(Color.cwBorder).frame(height: 1)
                content
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { service.start() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(service.sourceURL.lastPathComponent)
                    .font(CWFont.mono(size: CWFont.s14, weight: .semibold))
                    .foregroundColor(.cwFg1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitleText)
                    .font(CWFont.mono(size: CWFont.s11, weight: .regular))
                    .foregroundColor(.cwFg3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder private var statusBadge: some View {
        switch service.status {
        case .idle:
            CWToken(text: "queued", variant: .meta)
        case .decoding:
            CWToken(text: "decoding", variant: .info, indicator: .glyph("⏵"))
        case .transcribing:
            CWToken(text: "transcribing", variant: .active, live: true)
        case .done:
            CWToken(text: "done", variant: .downloaded, indicator: .glyph("✓"))
        case .failed:
            CWToken(text: "failed", variant: .missing, indicator: .glyph("!"))
        }
    }

    /// Subtitle line under the filename. Shows the source folder while in
    /// flight (so the user knows which file is processing if they dropped
    /// several), and the transcript stats once done.
    private var subtitleText: String {
        switch service.status {
        case .done(let t):
            return durationLabel(t.durationSeconds)
        default:
            return service.sourceURL.deletingLastPathComponent().path
        }
    }

    // MARK: - Body

    @ViewBuilder private var content: some View {
        switch service.status {
        case .idle, .decoding, .transcribing:
            progressView
        case .done(let transcript):
            doneView(transcript)
        case .failed(let message):
            failureView(message)
        }
    }

    // MARK: - In-flight states

    private var progressView: some View {
        VStack(spacing: 18) {
            Spacer()
            progressBar
            Text(progressCaption)
                .font(CWFont.mono(size: CWFont.s12, weight: .regular))
                .foregroundColor(.cwFg2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    @ViewBuilder private var progressBar: some View {
        switch service.status {
        case .decoding(let p):
            ProgressView(value: p)
                .tint(prefs.accent)
                .frame(maxWidth: 320)
        case .transcribing:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(prefs.accent)
                .controlSize(.regular)
        default:
            EmptyView()
        }
    }

    private var progressCaption: String {
        switch service.status {
        case .idle:                return "Preparing…"
        case .decoding(let p):     return "Decoding audio · \(Int((p * 100).rounded()))%"
        case .transcribing:        return "Whisper is transcribing…"
        default:                   return ""
        }
    }

    // MARK: - Done state

    private func doneView(_ transcript: FileTranscript) -> some View {
        VStack(spacing: 0) {
            transcriptScroll(transcript)
            Rectangle().fill(Color.cwBorder).frame(height: 1)
            footer(transcript)
        }
    }

    private func transcriptScroll(_ transcript: FileTranscript) -> some View {
        ScrollView {
            Text(transcript.plainText.isEmpty
                 ? "(No speech detected.)"
                 : transcript.plainText)
                .font(CWFont.mono(size: CWFont.s13, weight: .regular))
                .foregroundColor(transcript.plainText.isEmpty ? .cwFg3 : .cwFg1)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
        }
        .frame(maxHeight: .infinity)
    }

    private func footer(_ transcript: FileTranscript) -> some View {
        HStack(spacing: 10) {
            Text(footerStats(transcript))
                .font(CWFont.mono(size: CWFont.s10, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(.cwFg3)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            CWButton(title: "Copy",
                     variant: .ghost,
                     indicator: .glyph("⌘")) {
                copyToPasteboard(transcript.plainText)
            }
            CWButton(title: "Save as…",
                     variant: .primary,
                     indicator: .glyph("↓")) {
                presentSavePanel(for: transcript)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func footerStats(_ t: FileTranscript) -> String {
        let words = t.plainText.split { $0.isWhitespace }.count
        let segs  = t.segments.count
        return "\(words) WORDS · \(segs) SEGMENTS · \(durationLabel(t.durationSeconds))"
    }

    // MARK: - Failure state

    private func failureView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription failed")
                .font(CWFont.mono(size: CWFont.s14, weight: .semibold))
                .foregroundColor(.cwDanger)
            Text(message)
                .font(CWFont.mono(size: CWFont.s12, weight: .regular))
                .foregroundColor(.cwFg2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    // MARK: - Helpers

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let totalSecs = Int(seconds.rounded())
        let h = totalSecs / 3600
        let m = (totalSecs / 60) % 60
        let s = totalSecs % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    // MARK: - Backdrop
    //
    // Same recipe as `OnboardingView.backdrop` — flat gradient with a soft
    // accent glow. Reads consistently with the Settings/Onboarding windows.

    @ViewBuilder private var backdrop: some View {
        ZStack {
            LinearGradient.cwBackdrop
            Circle().fill(prefs.accent.opacity(0.08))
                .frame(width: 480, height: 480).blur(radius: 110)
                .offset(x: 120, y: -180)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: - Actions

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// `NSSavePanel` showing all three formats. The user picks the extension
    /// from the panel's built-in type popup; we look at the chosen URL's
    /// `pathExtension` to decide which exporter to run.
    private func presentSavePanel(for transcript: FileTranscript) {
        let panel = NSSavePanel()
        panel.title = "Save Transcript"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            transcript.sourceURL.deletingPathExtension().lastPathComponent + ".txt"
        panel.directoryURL = transcript.sourceURL.deletingLastPathComponent()

        // `.plainText` is the default; the SRT/VTT entries appear in the
        // save panel's "File Format" popup so the user can switch in one
        // gesture without leaving the dialog.
        var types: [UTType] = [.plainText]
        if let srt = UTType(filenameExtension: "srt") { types.append(srt) }
        if let vtt = UTType(filenameExtension: "vtt") { types.append(vtt) }
        panel.allowedContentTypes = types

        guard panel.runModal() == .OK, let dest = panel.url else { return }

        let body: String
        switch dest.pathExtension.lowercased() {
        case "srt": body = TranscriptExporter.srt(transcript)
        case "vtt": body = TranscriptExporter.vtt(transcript)
        default:    body = TranscriptExporter.text(transcript)
        }

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
