import Foundation
import AVFoundation
import Accelerate

enum AudioCaptureError: Error {
    case permissionDenied
    case engineFailedToStart(Error)
}

final class AudioCaptureEngine {
    /// Whisper expects 16kHz mono float32.
    static let targetSampleRate: Double = 16_000

    /// Buffer up to ~30 seconds of audio (16k samples/sec * 30 = 480k floats).
    private let buffer = AudioRingBuffer(capacity: 480_000)

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    /// Called on the main thread with a normalised RMS level (0...1) for waveform UI.
    var onLevel: ((Float) -> Void)?

    /// Called on the main thread with each new chunk of 16kHz mono Float32 samples
    /// captured from the microphone.
    var onSamples: (([Float]) -> Void)?

    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) != .denied else {
            throw AudioCaptureError.permissionDenied
        }

        // Async permission ask if needed — first call returns notDetermined.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.engineFailedToStart(NSError(
                domain: "CyphrWhispr.Audio", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create target audio format"]
            ))
        }

        targetFormat = target
        converter = AVAudioConverter(from: inputFormat, to: target)

        buffer.reset()
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] pcm, _ in
            self?.handle(pcm: pcm)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw AudioCaptureError.engineFailedToStart(error)
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }

    /// Returns and clears the buffer of float32 samples accumulated so far.
    func drainSamples() -> [Float] {
        buffer.readAll()
    }

    private func handle(pcm: AVAudioPCMBuffer) {
        guard let converter, let target = targetFormat else { return }

        let ratio = target.sampleRate / pcm.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio + 16)
        guard let out = AVAudioPCMBuffer(
            pcmFormat: target,
            frameCapacity: outCapacity
        ) else { return }

        var error: NSError?
        var didProvide = false
        let status = converter.convert(to: out, error: &error) { _, status in
            if didProvide {
                status.pointee = .noDataNow
                return nil
            }
            didProvide = true
            status.pointee = .haveData
            return pcm
        }

        guard status != .error, error == nil else { return }
        guard let channelData = out.floatChannelData?[0] else { return }
        let frameCount = Int(out.frameLength)
        guard frameCount > 0 else { return }

        buffer.write(channelData, count: frameCount)

        // Snapshot samples for the streaming consumer on the main thread.
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Compute RMS for the waveform UI.
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
        let level = min(1, max(0, rms * 6))

        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(level)
            self?.onSamples?(samples)
        }
    }
}
