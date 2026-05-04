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

    @MainActor
    func testPillController_spawnsOnFirstShow_thenInstantOnSecond() async {
        let controller = PillWindowController()

        // First show — should set phase to .spawning(progress: 0).
        controller.show()
        try? await Task.sleep(nanoseconds: 50_000_000)  // give playSpawn one tick

        if case .spawning = controller.viewModelForTesting.phase {
            // pass
        } else {
            XCTFail("first show() must trigger .spawning phase, got \(controller.viewModelForTesting.phase)")
        }

        // Cancel + hide
        controller.hide()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Second show — should be instant .armed.
        controller.show()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.viewModelForTesting.phase, .armed,
                       "second show() in same session must skip the spawn")

        controller.hide()
    }

    @MainActor
    func testPillController_replaysSpawnAfterModelChange() async {
        let controller = PillWindowController()

        controller.show()  // burns the first spawn
        try? await Task.sleep(nanoseconds: 50_000_000)
        controller.hide()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Simulate the user changing the active model in Settings.
        NotificationCenter.default.post(name: .activeModelDidChange, object: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)  // let observer fire

        controller.show()
        try? await Task.sleep(nanoseconds: 50_000_000)

        if case .spawning = controller.viewModelForTesting.phase {
            // pass — spawnPending was reset by the notification
        } else {
            XCTFail("show() after activeModelDidChange must replay spawn, got \(controller.viewModelForTesting.phase)")
        }
        controller.hide()
    }
}
