import Foundation

/// Pure formatters that turn a `FileTranscript` into the three text formats
/// the result-window's Save as… dialog offers:
///
///   • `text(_:)` — plain transcript, one paragraph, no timestamps.
///   • `srt(_:)`  — SubRip subtitles. `00:00:00,000 --> 00:00:02,500`,
///                  segment numbers from 1, comma decimal separator.
///   • `vtt(_:)`  — WebVTT subtitles. Same layout as SRT but with a period
///                  decimal separator, `WEBVTT` header, no segment numbers.
///
/// Deterministic given the same input — which is why this is a flat enum of
/// static functions instead of a stateful actor. Keeps the exporter trivially
/// unit-testable; see `TranscriptExporterTests`.
enum TranscriptExporter {
    // MARK: - Public entry points

    /// Plain transcript text. Same value as `transcript.plainText` — exposed
    /// through this entry point so the Save as… code path looks symmetric
    /// across the three formats.
    static func text(_ transcript: FileTranscript) -> String {
        transcript.plainText
    }

    /// SubRip (`.srt`). Index starts at 1, comma decimal separator on the
    /// time stamps, blank line between cues. The format VLC and almost every
    /// non-browser video player consume.
    static func srt(_ transcript: FileTranscript) -> String {
        var out = ""
        for (i, seg) in transcript.segments.enumerated() {
            let trimmed = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            out += "\(i + 1)\n"
            out += "\(srtTimestamp(seg.start)) --> \(srtTimestamp(seg.end))\n"
            out += trimmed
            out += "\n\n"
        }
        return out
    }

    /// WebVTT (`.vtt`). Required `WEBVTT` header, period decimal separator,
    /// no segment numbers, blank line between cues. The format HTML5 `<track>`
    /// elements and YouTube auto-captions consume.
    static func vtt(_ transcript: FileTranscript) -> String {
        var out = "WEBVTT\n\n"
        for seg in transcript.segments {
            let trimmed = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            out += "\(vttTimestamp(seg.start)) --> \(vttTimestamp(seg.end))\n"
            out += trimmed
            out += "\n\n"
        }
        return out
    }

    // MARK: - Timestamp helpers (kept internal so tests can verify them
    // directly without going through full transcripts)

    /// `HH:MM:SS,mmm` — comma decimal, the SRT spec.
    static func srtTimestamp(_ seconds: TimeInterval) -> String {
        let (h, m, s, ms) = breakdown(seconds)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    /// `HH:MM:SS.mmm` — period decimal, the WebVTT spec.
    static func vttTimestamp(_ seconds: TimeInterval) -> String {
        let (h, m, s, ms) = breakdown(seconds)
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }

    /// Decompose a non-negative time interval into hours/minutes/seconds/ms.
    /// Negative inputs clamp to zero — Whisper occasionally emits very small
    /// negative starts on the first segment of a long file and we don't want
    /// `-0:00:00,001` to leak into the exports.
    private static func breakdown(_ seconds: TimeInterval) -> (Int, Int, Int, Int) {
        let clamped = max(0, seconds)
        let totalMillis = Int((clamped * 1000).rounded())
        let h = totalMillis / 3_600_000
        let m = (totalMillis / 60_000) % 60
        let s = (totalMillis / 1000) % 60
        let ms = totalMillis % 1000
        return (h, m, s, ms)
    }
}
