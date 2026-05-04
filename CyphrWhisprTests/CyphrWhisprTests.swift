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
}
