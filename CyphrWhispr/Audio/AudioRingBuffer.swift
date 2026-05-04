import Foundation
import os.lock

/// Single-producer / single-consumer ring buffer of Float32 samples.
/// Producer is the audio engine tap thread; consumer is the transcription task.
final class AudioRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private var storage: UnsafeMutablePointer<Float>
    private var head: Int = 0
    private var tail: Int = 0
    private var lock = os_unfair_lock()

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    func write(_ samples: UnsafePointer<Float>, count: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        var written = 0
        while written < count {
            let chunk = min(count - written, capacity - head)
            (storage + head).update(from: samples + written, count: chunk)
            head = (head + chunk) % capacity
            written += chunk
            if head == tail {
                tail = (tail + 1) % capacity
            }
        }
    }

    func readAll() -> [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        var out: [Float] = []
        if head == tail { return out }

        if tail < head {
            out.append(contentsOf: UnsafeBufferPointer(start: storage + tail, count: head - tail))
        } else {
            out.append(contentsOf: UnsafeBufferPointer(start: storage + tail, count: capacity - tail))
            out.append(contentsOf: UnsafeBufferPointer(start: storage, count: head))
        }
        tail = head
        return out
    }

    func reset() {
        os_unfair_lock_lock(&lock)
        head = 0
        tail = 0
        os_unfair_lock_unlock(&lock)
    }
}
