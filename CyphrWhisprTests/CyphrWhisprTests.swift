import XCTest
@testable import CyphrWhispr

final class CyphrWhisprTests: XCTestCase {
    func testRingBufferRoundTrip() {
        let buffer = AudioRingBuffer(capacity: 8)
        let samples: [Float] = [1, 2, 3, 4, 5]
        samples.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: samples.count)
        }
        XCTAssertEqual(buffer.readAll(), samples)
        XCTAssertEqual(buffer.readAll(), [])
    }

    func testRingBufferOverflowDropsOldest() {
        let buffer = AudioRingBuffer(capacity: 4)
        let samples: [Float] = [1, 2, 3, 4, 5, 6]
        samples.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: samples.count)
        }
        let read = buffer.readAll()
        XCTAssertEqual(read.count, 4)
        XCTAssertEqual(read.last, 6)
    }

    @MainActor
    func testActiveModelChange_postsNotification() async {
        let store = PreferencesStore.shared
        let initial = store.activeModelID
        // Defer the restore so cleanup runs even if the expectation times out
        // or a later assertion crashes — `PreferencesStore.shared` is a
        // process-wide singleton backed by UserDefaults, so a leaked value
        // would persist across test runs and pollute the developer's prefs.
        defer { store.activeModelID = initial }

        let other = (initial == "openai_whisper-small.en")
            ? "openai_whisper-tiny.en"
            : "openai_whisper-small.en"

        let exp = expectation(forNotification: .activeModelDidChange,
                              object: store,
                              handler: nil)

        store.activeModelID = other
        await fulfillment(of: [exp], timeout: 1.0)
    }

    @MainActor
    func testPlaySpawn_progressesFromZeroToArmed() async {
        let vm = PillViewModel()
        XCTAssertEqual(vm.phase, .idle)

        // Use a short duration so the test runs quickly. The implementation
        // is duration-agnostic — same logic, faster wall-clock.
        await vm.playSpawn(duration: 0.20)

        XCTAssertEqual(vm.phase, .armed,
                       "spawn should complete by setting phase to .armed")
    }

    @MainActor
    func testCancelSpawn_stopsTimeline_keepsLastPhase() async {
        let vm = PillViewModel()
        let task = Task { await vm.playSpawn(duration: 1.0) }

        // Let the spawn run for a slice, then cancel.
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        vm.cancelSpawn()
        await task.value

        // Phase should still be .spawning(...) — cancel does NOT advance to .armed.
        if case .spawning = vm.phase {
            // pass
        } else {
            XCTFail("after cancellation, phase should still be .spawning, got \(vm.phase)")
        }
    }
}
