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
}
