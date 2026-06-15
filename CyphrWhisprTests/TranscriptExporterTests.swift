import XCTest
@testable import CyphrWhispr

/// Unit tests for `TranscriptExporter` — the formatter that turns a
/// `FileTranscript`'s segments into plain text, SRT, or VTT for the
/// file-transcription result window's Save as… dialog.
///
/// These are deliberately exhaustive on the timestamp formatting (which is
/// where subtitle players are picky about format conformance) and lighter
/// on the cue body (which is just trimmed segment text).
final class TranscriptExporterTests: XCTestCase {

    // MARK: - Timestamp formatting

    /// SRT timestamps use a comma decimal separator per the format's spec —
    /// `HH:MM:SS,mmm`. VLC, ffmpeg, and most subtitle stacks reject period
    /// decimal here.
    func testSrtTimestampUsesCommaDecimal() {
        XCTAssertEqual(TranscriptExporter.srtTimestamp(0),     "00:00:00,000")
        XCTAssertEqual(TranscriptExporter.srtTimestamp(0.5),   "00:00:00,500")
        XCTAssertEqual(TranscriptExporter.srtTimestamp(1.234), "00:00:01,234")
    }

    /// VTT timestamps use a period decimal separator per the WebVTT spec —
    /// `HH:MM:SS.mmm`. HTML5 `<track>` and browsers reject comma decimal.
    func testVttTimestampUsesPeriodDecimal() {
        XCTAssertEqual(TranscriptExporter.vttTimestamp(0),     "00:00:00.000")
        XCTAssertEqual(TranscriptExporter.vttTimestamp(0.5),   "00:00:00.500")
        XCTAssertEqual(TranscriptExporter.vttTimestamp(1.234), "00:00:01.234")
    }

    /// Hour boundary crossing — `3661.5 s` → `1 h 1 m 1.5 s`.
    func testTimestampHandlesHourBoundary() {
        XCTAssertEqual(TranscriptExporter.srtTimestamp(3661.5), "01:01:01,500")
        XCTAssertEqual(TranscriptExporter.vttTimestamp(3661.5), "01:01:01.500")
    }

    /// Sub-millisecond rounding — `0.9999 s` rounds up to `1.000`.
    func testTimestampRoundsHalfToNearest() {
        XCTAssertEqual(TranscriptExporter.srtTimestamp(0.9999), "00:00:01,000")
        XCTAssertEqual(TranscriptExporter.vttTimestamp(0.9999), "00:00:01.000")
    }

    /// Negative starts (which Whisper occasionally emits on the first
    /// segment of a long file) clamp to zero so the exports never contain
    /// `-0:00:00,001`.
    func testTimestampClampsNegativeToZero() {
        XCTAssertEqual(TranscriptExporter.srtTimestamp(-0.001), "00:00:00,000")
        XCTAssertEqual(TranscriptExporter.vttTimestamp(-1.5),   "00:00:00.000")
    }

    // MARK: - SRT body

    func testSrtEmptyTranscriptProducesEmptyString() {
        let t = FileTranscript(sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
                               durationSeconds: 0,
                               segments: [])
        XCTAssertEqual(TranscriptExporter.srt(t), "")
    }

    /// Single segment — index `1`, comma decimal timestamps, blank line at
    /// the end.
    func testSrtSingleSegment() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 2.5,
            segments: [.init(start: 0, end: 2.5, text: "Hello there.")]
        )
        let expected =
            "1\n" +
            "00:00:00,000 --> 00:00:02,500\n" +
            "Hello there.\n\n"
        XCTAssertEqual(TranscriptExporter.srt(t), expected)
    }

    /// Multiple segments — indices ascend from `1`.
    func testSrtNumbersSegmentsStartingAtOne() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 6,
            segments: [
                .init(start: 0, end: 2, text: "First."),
                .init(start: 2, end: 4, text: "Second."),
                .init(start: 4, end: 6, text: "Third."),
            ]
        )
        let body = TranscriptExporter.srt(t)
        XCTAssertTrue(body.hasPrefix("1\n00:00:00,000 --> 00:00:02,000\nFirst.\n\n2\n"))
        XCTAssertTrue(body.contains("\n3\n00:00:04,000 --> 00:00:06,000\nThird.\n\n"))
    }

    /// Whitespace-only segments are skipped entirely — they'd render as
    /// empty cues otherwise, which most players treat as malformed.
    func testSrtSkipsWhitespaceOnlySegments() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 4,
            segments: [
                .init(start: 0, end: 2, text: "Real."),
                .init(start: 2, end: 4, text: "   \n  "),
            ]
        )
        let body = TranscriptExporter.srt(t)
        XCTAssertTrue(body.contains("Real."))
        XCTAssertFalse(body.contains("00:00:02,000 --> 00:00:04,000"))
    }

    /// Per-segment text is trimmed of surrounding whitespace before write —
    /// Whisper segments often have a leading space.
    func testSrtTrimsSegmentText() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 2,
            segments: [.init(start: 0, end: 2, text: "  spaced   ")]
        )
        XCTAssertTrue(TranscriptExporter.srt(t).contains("\nspaced\n"))
    }

    // MARK: - VTT body

    /// Even an empty transcript still gets the mandatory `WEBVTT` header —
    /// players reject the file otherwise.
    func testVttEmptyTranscriptKeepsHeader() {
        let t = FileTranscript(sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
                               durationSeconds: 0,
                               segments: [])
        XCTAssertEqual(TranscriptExporter.vtt(t), "WEBVTT\n\n")
    }

    /// Single segment — period decimal timestamps, no segment number, blank
    /// line after the cue.
    func testVttSingleSegment() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 2.5,
            segments: [.init(start: 0, end: 2.5, text: "Hello there.")]
        )
        let expected =
            "WEBVTT\n\n" +
            "00:00:00.000 --> 00:00:02.500\n" +
            "Hello there.\n\n"
        XCTAssertEqual(TranscriptExporter.vtt(t), expected)
    }

    /// VTT never emits segment numbers — that's the visible difference from
    /// SRT besides the decimal separator.
    func testVttHasNoSegmentNumbers() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 4,
            segments: [
                .init(start: 0, end: 2, text: "First."),
                .init(start: 2, end: 4, text: "Second."),
            ]
        )
        let body = TranscriptExporter.vtt(t)
        XCTAssertFalse(body.contains("\n1\n"))
        XCTAssertFalse(body.contains("\n2\n"))
    }

    // MARK: - Plain text passthrough

    /// `text(_:)` returns the same value as `FileTranscript.plainText` so
    /// the save-panel code path looks symmetric across the three formats.
    func testTextMatchesTranscriptPlainText() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 4,
            segments: [
                .init(start: 0, end: 2, text: "Hello"),
                .init(start: 2, end: 4, text: "there."),
            ]
        )
        XCTAssertEqual(TranscriptExporter.text(t), "Hello there.")
        XCTAssertEqual(TranscriptExporter.text(t), t.plainText)
    }

    // MARK: - Timestamped text + silence

    /// A >1s gap between two segments produces a silence line between them,
    /// carrying the real gap length in parentheses.
    func testTimestampedTextMarksGapBetweenSegments() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 14,
            segments: [
                .init(start: 0, end: 5, text: "Hello and welcome."),
                .init(start: 8, end: 14, text: "Now we continue."),
            ]
        )
        let body = TranscriptExporter.timestampedText(t)
        XCTAssertTrue(body.contains("[00:00 → 00:05]  Hello and welcome."))
        XCTAssertTrue(body.contains("[00:05 → 00:08]  — silence (3.0s) —"))
        XCTAssertTrue(body.contains("[00:08 → 00:14]  Now we continue."))
    }

    /// A sub-threshold gap (<1s) produces no silence line — the segments sit
    /// back-to-back.
    func testTimestampedTextIgnoresSubThresholdGap() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 4,
            segments: [
                .init(start: 0, end: 2, text: "First."),
                .init(start: 2.5, end: 4, text: "Second."),
            ]
        )
        XCTAssertFalse(TranscriptExporter.timestampedText(t).contains("silence"))
    }

    /// Leading silence — a first word that starts >1s in gets a silence line
    /// covering 0:00 → firstStart.
    func testTimestampedTextMarksLeadingSilence() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 10,
            segments: [.init(start: 4, end: 10, text: "Late start.")]
        )
        XCTAssertTrue(
            TranscriptExporter.timestampedText(t)
                .hasPrefix("[00:00 → 00:04]  — silence (4.0s) —")
        )
    }

    /// Trailing silence — a last word that ends >1s before the file's end
    /// gets a silence line covering lastEnd → duration.
    func testTimestampedTextMarksTrailingSilence() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 12,
            segments: [.init(start: 0, end: 5, text: "Early finish.")]
        )
        XCTAssertTrue(
            TranscriptExporter.timestampedText(t)
                .contains("[00:05 → 00:12]  — silence (7.0s) —")
        )
    }

    /// A file with no transcribed speech collapses to a single whole-file
    /// silence span (instrumental track, dead air).
    func testTimestampedTextNoSpeechIsWholeFileSilence() {
        let t = FileTranscript(sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
                               durationSeconds: 30,
                               segments: [])
        XCTAssertEqual(TranscriptExporter.timestampedText(t),
                       "[00:00 → 00:30]  — silence (30.0s) —\n")
    }

    /// No speech AND a sub-threshold duration → empty output (nothing worth
    /// marking).
    func testTimestampedTextNoSpeechShortIsEmpty() {
        let t = FileTranscript(sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
                               durationSeconds: 0.5,
                               segments: [])
        XCTAssertEqual(TranscriptExporter.timestampedText(t), "")
    }

    /// Overlapping / out-of-order segment ends never produce a negative
    /// silence — the cursor never walks backwards.
    func testTimestampedTextHandlesOverlappingSegments() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 6,
            segments: [
                .init(start: 0, end: 4, text: "Long one."),
                .init(start: 2, end: 6, text: "Overlaps."),
            ]
        )
        let body = TranscriptExporter.timestampedText(t)
        XCTAssertFalse(body.contains("silence"))
        XCTAssertTrue(body.contains("Long one."))
        XCTAssertTrue(body.contains("Overlaps."))
    }

    /// The parenthesised silence duration preserves the real gap even when
    /// the rounded endpoints look like a smaller gap — a 1.4s pause reads
    /// "(1.4s)" though its endpoints round to 00:05 → 00:06.
    func testTimestampedTextSilenceDurationKeepsSubSecondGap() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 10,
            segments: [
                .init(start: 0, end: 5.0, text: "Before."),
                .init(start: 6.4, end: 10, text: "After."),
            ]
        )
        XCTAssertTrue(
            TranscriptExporter.timestampedText(t).contains("— silence (1.4s) —")
        )
    }

    // MARK: - clockTimestamp

    /// MM:SS under an hour, H:MM:SS past it; negatives clamp to zero.
    func testClockTimestampFormat() {
        XCTAssertEqual(TranscriptExporter.clockTimestamp(0),    "00:00")
        XCTAssertEqual(TranscriptExporter.clockTimestamp(65),   "01:05")
        XCTAssertEqual(TranscriptExporter.clockTimestamp(3661), "1:01:01")
        XCTAssertEqual(TranscriptExporter.clockTimestamp(-5),   "00:00")
    }

    // MARK: - Export-format metadata

    /// The two text formats share the `.txt` extension (the reason the save
    /// panel needs a custom format popup); the subtitle formats don't.
    func testExportFormatExtensions() {
        XCTAssertEqual(TranscriptExportFormat.plainText.fileExtension,       "txt")
        XCTAssertEqual(TranscriptExportFormat.timestampedText.fileExtension, "txt")
        XCTAssertEqual(TranscriptExportFormat.srt.fileExtension,             "srt")
        XCTAssertEqual(TranscriptExportFormat.vtt.fileExtension,             "vtt")
    }

    /// Each format's `render` routes to the matching exporter — spot-check by
    /// the distinguishing marker of each output.
    func testExportFormatRenderRoutesToExporter() {
        let t = FileTranscript(
            sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"),
            durationSeconds: 2.5,
            segments: [.init(start: 0, end: 2.5, text: "Hi.")]
        )
        XCTAssertEqual(TranscriptExportFormat.plainText.render(t), "Hi.")
        XCTAssertTrue(TranscriptExportFormat.timestampedText.render(t).contains("[00:00 → 00:02]  Hi."))
        XCTAssertTrue(TranscriptExportFormat.srt.render(t).hasPrefix("1\n"))
        XCTAssertTrue(TranscriptExportFormat.vtt.render(t).hasPrefix("WEBVTT"))
    }
}
