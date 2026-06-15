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

    /// Human-readable timestamped transcript with inline silence markers.
    ///
    /// Unlike the subtitle exports, this is meant to be *read* — a log of
    /// what was said, when, with explicit "— silence —" lines wherever the
    /// speaker paused for longer than `silenceThreshold`:
    ///
    ///     [00:00 → 00:05]  Hello and welcome to the show.
    ///     [00:05 → 00:08]  — silence (3.0s) —
    ///     [00:08 → 00:14]  Today we're discussing timestamps.
    ///
    /// Silence is **gap-based**: any span longer than the threshold between
    /// one segment's end and the next's start becomes a silence line, as
    /// does leading silence before the first word and trailing silence after
    /// the last (measured against `durationSeconds`). This marks "where no
    /// speech was transcribed" — which means non-speech audio (background
    /// music, noise) counts as silence here, since Whisper emits no words
    /// for it. That's the deliberate, simpler reading of "silence"; a true
    /// waveform-energy VAD would be a separate, more involved pass.
    ///
    /// The threshold default (1s) matches the product spec. Endpoints are
    /// rounded to whole seconds for readability; the parenthesised duration
    /// preserves the real sub-second gap length so a 1.4s pause still reads
    /// as "(1.4s)" even when its endpoints round to the same second.
    static func timestampedText(_ transcript: FileTranscript,
                                silenceThreshold: TimeInterval = 1.0) -> String {
        // Trim + drop empty segments first so a blank segment can't split a
        // single real silence into two sub-threshold halves that both vanish.
        let segments: [(start: TimeInterval, end: TimeInterval, text: String)] =
            transcript.segments
                .map { (start: $0.start,
                        end: $0.end,
                        text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.text.isEmpty }

        // No speech at all → the whole file is one silence span (instrumental
        // track, dead air, etc.). Only emit it if it clears the threshold.
        guard !segments.isEmpty else {
            if transcript.durationSeconds >= silenceThreshold {
                return silenceLine(from: 0, to: transcript.durationSeconds) + "\n"
            }
            return ""
        }

        var lines: [String] = []
        // `cursor` is the end of the last thing we accounted for. Starts at 0
        // so the first iteration's gap check doubles as leading-silence
        // detection (silence between 0:00 and the first word).
        var cursor: TimeInterval = 0
        for seg in segments {
            if seg.start - cursor >= silenceThreshold {
                lines.append(silenceLine(from: cursor, to: seg.start))
            }
            lines.append("[\(clockTimestamp(seg.start)) → \(clockTimestamp(seg.end))]  \(seg.text)")
            // max() guards against overlapping/out-of-order segments — never
            // let the cursor walk backwards, or we'd emit a negative silence.
            cursor = max(cursor, seg.end)
        }
        // Trailing silence after the last word, measured to total duration.
        if transcript.durationSeconds - cursor >= silenceThreshold {
            lines.append(silenceLine(from: cursor, to: transcript.durationSeconds))
        }
        return lines.joined(separator: "\n") + "\n"
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

    /// `MM:SS` under an hour, `H:MM:SS` past it — readable wall-clock style
    /// for the human-facing timestamped text export. No milliseconds: the
    /// subtitle exports carry sub-second precision when that matters, but a
    /// readable log doesn't need it.
    ///
    /// Truncates rather than rounds — `2.9s` reads as `00:02`, matching the
    /// "which whole second are we in" convention every media player uses for
    /// elapsed time. Sub-second precision that *does* matter (silence gap
    /// length) is carried separately in the parenthesised duration, so the
    /// display never has to round.
    static func clockTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total / 60) % 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// One "— silence (Ns) —" line spanning `[from, to]`. The parenthesised
    /// duration is the *real* gap length (one decimal), independent of the
    /// whole-second rounding the endpoints get from `clockTimestamp`.
    private static func silenceLine(from start: TimeInterval, to end: TimeInterval) -> String {
        let dur = max(0, end - start)
        let durText = String(format: "%.1f", dur)
        return "[\(clockTimestamp(start)) → \(clockTimestamp(end))]  — silence (\(durText)s) —"
    }
}

/// The export formats the result window's Save as… offers. Centralises each
/// format's menu title, file extension, and exporter call so the save-panel
/// code stays a flat list rather than a switch scattered across the view.
///
/// Plain text and timestamped text deliberately share the `.txt` extension —
/// that's why the save panel uses a custom format-chooser popup
/// (`TranscriptSavePanel`) instead of NSSavePanel's built-in File Format
/// popup, which can only tell formats apart by extension/UTType.
enum TranscriptExportFormat: CaseIterable, Identifiable {
    case plainText
    case timestampedText
    case srt
    case vtt

    var id: Self { self }

    /// Title shown in the save panel's format popup.
    var menuTitle: String {
        switch self {
        case .plainText:       return "Plain text (.txt)"
        case .timestampedText: return "Timestamped + silence (.txt)"
        case .srt:             return "SubRip subtitles (.srt)"
        case .vtt:             return "WebVTT subtitles (.vtt)"
        }
    }

    var fileExtension: String {
        switch self {
        case .plainText, .timestampedText: return "txt"
        case .srt:                         return "srt"
        case .vtt:                         return "vtt"
        }
    }

    /// Render `transcript` into this format's text body.
    func render(_ transcript: FileTranscript) -> String {
        switch self {
        case .plainText:       return TranscriptExporter.text(transcript)
        case .timestampedText: return TranscriptExporter.timestampedText(transcript)
        case .srt:             return TranscriptExporter.srt(transcript)
        case .vtt:             return TranscriptExporter.vtt(transcript)
        }
    }
}
