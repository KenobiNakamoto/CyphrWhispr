import Foundation
import AVFoundation

enum AssetAudioDecodingError: Error, LocalizedError {
    case noAudioTrack
    case readerSetupFailed(Error)
    case decodeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "This file doesn't contain an audio track."
        case .readerSetupFailed(let e):
            return "Couldn't read this file: \(e.localizedDescription)"
        case .decodeFailed(let e):
            return "Decoding failed: \(e.localizedDescription)"
        }
    }
}

/// Decodes any AVFoundation-readable audio or video file into a flat array of
/// 16 kHz mono Float32 samples — the format `WhisperKit.transcribe(audioArray:)`
/// expects.
///
/// `AVURLAsset` accepts everything Apple ships codecs for: MP3 / M4A / WAV /
/// AIFF / CAF / FLAC, plus every audio-bearing video container Apple supports
/// (MOV / MP4 / M4V). Anything outside that surface — Opus, Vorbis-in-WebM,
/// DRM'd `m4p` — comes back as `.noAudioTrack` or `.decodeFailed` from the
/// reader.
///
/// Resampling and downmix are delegated to AVFoundation by configuring
/// `AVAssetReaderTrackOutput.outputSettings` with the target PCM format.
/// Simpler than the explicit `AVAudioConverter` pipeline `AudioCaptureEngine`
/// runs on the live mic tap — and uses the same Accelerate-backed converter
/// under the hood, so file-mode samples look bit-identical to the model.
enum AssetAudioDecoder {
    private static let targetSampleRate: Double = 16_000

    /// Stream the file through `AVAssetReader`, gather 16 kHz mono Float32
    /// samples, and report progress along the way.
    ///
    /// `progressHandler` is invoked from the calling Task (which is *not*
    /// the main actor — the decode runs on the global executor so it doesn't
    /// stall UI). Values are in `0...1`. Pass nil if you don't care.
    static func decode(url: URL,
                       progressHandler: ((Double) -> Void)? = nil) async throws -> [Float] {
        let asset = AVURLAsset(url: url)

        // Modern async track accessor — the synchronous `asset.tracks` is
        // deprecated and asserts on newer SDKs.
        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw AssetAudioDecodingError.readerSetupFailed(error)
        }
        guard let track = audioTracks.first else {
            throw AssetAudioDecodingError.noAudioTrack
        }

        // Total duration drives the progress curve. Falls back to 0 if
        // AVFoundation can't tell us (rare — only happens on certain network-
        // backed assets); progress then stays at 0 until completion.
        let totalSeconds: Double
        do {
            let cmDuration = try await asset.load(.duration)
            totalSeconds = max(0, CMTimeGetSeconds(cmDuration))
        } catch {
            totalSeconds = 0
        }

        // Ask AVFoundation to give us samples already resampled to 16 kHz
        // mono Float32. Doing it here, rather than running our own
        // `AVAudioConverter` over the raw track samples, means we lean on the
        // same Apple-shipped converter that `AVAudioConverter` wraps — no
        // behavioural drift between file-mode and live-mode.
        //
        // Mono output means we don't need to specify `AVLinearPCMIsNonInterleaved`
        // (interleaved vs non-interleaved is a no-op for 1 channel).
        let outputSettings: [String: Any] = [
            AVFormatIDKey:               kAudioFormatLinearPCM,
            AVSampleRateKey:             targetSampleRate,
            AVNumberOfChannelsKey:       1,
            AVLinearPCMBitDepthKey:      32,
            AVLinearPCMIsFloatKey:       true,
            AVLinearPCMIsBigEndianKey:   false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        // We copy into our own array — no need for AVFoundation to copy first.
        output.alwaysCopiesSampleData = false

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AssetAudioDecodingError.readerSetupFailed(error)
        }
        guard reader.canAdd(output) else {
            throw AssetAudioDecodingError.readerSetupFailed(NSError(
                domain: "CyphrWhispr.FileDecode", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Reader rejected the audio output config"]
            ))
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AssetAudioDecodingError.readerSetupFailed(reader.error ?? NSError(
                domain: "CyphrWhispr.FileDecode", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Reader failed to start"]
            ))
        }

        // Pre-size the output buffer to dodge quadratic reallocation on long
        // files — a 2 h podcast at 16 kHz is ~115 M floats (~460 MB) and
        // grow-and-copy in a tight loop would be unkind.
        var samples: [Float] = []
        if totalSeconds > 0 {
            samples.reserveCapacity(Int(totalSeconds * targetSampleRate) + 16)
        }

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            try Self.appendSamples(from: sampleBuffer, into: &samples)
            if let progressHandler, totalSeconds > 0 {
                let elapsed = Double(samples.count) / targetSampleRate
                progressHandler(min(1.0, elapsed / totalSeconds))
            }
            // Cooperative yield so a cancelled job can actually exit. Without
            // this, the decode loop hogs its task and Task.isCancelled is
            // never observed mid-decode.
            await Task.yield()
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
        }

        switch reader.status {
        case .completed:
            progressHandler?(1.0)
            return samples
        case .failed, .cancelled:
            throw AssetAudioDecodingError.decodeFailed(reader.error ?? NSError(
                domain: "CyphrWhispr.FileDecode", code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Reader stopped before completion"]
            ))
        default:
            // The loop only exits via break, completed, failed, or cancelled,
            // so `.reading` here shouldn't happen — covered for exhaustiveness.
            return samples
        }
    }

    /// Extract Float32 sample data from a CMSampleBuffer the reader produced
    /// and append it to `samples`. The buffer is laid out as raw Float32
    /// channel data (we requested it that way via `outputSettings`), so we
    /// can read it as `[Float]` directly without per-sample conversion.
    private static func appendSamples(from sampleBuffer: CMSampleBuffer,
                                      into samples: inout [Float]) throws {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer,
                                                 atOffset: 0,
                                                 lengthAtOffsetOut: nil,
                                                 totalLengthOut: &totalLength,
                                                 dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let dataPointer else {
            throw AssetAudioDecodingError.decodeFailed(NSError(
                domain: "CyphrWhispr.FileDecode", code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't read sample buffer data"]
            ))
        }
        let floatCount = totalLength / MemoryLayout<Float>.size
        guard floatCount > 0 else { return }
        dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { floatPtr in
            let buf = UnsafeBufferPointer(start: floatPtr, count: floatCount)
            samples.append(contentsOf: buf)
        }
    }
}
