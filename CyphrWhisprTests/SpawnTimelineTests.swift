import XCTest
@testable import CyphrWhispr

final class SpawnTimelineTests: XCTestCase {

    // MARK: - Spawn phase (0 → 0.167)

    func test_atTimeZero_figuresAreInvisibleAtSeedScale() {
        let s = SpawnTimeline.state(at: 0)
        XCTAssertEqual(s.figureOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(s.figureScale, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.pillWidth, 45, accuracy: 0.001)
        XCTAssertEqual(s.triangleX, 3.5, accuracy: 0.001)
        XCTAssertEqual(s.dotX, 25, accuracy: 0.001)
        XCTAssertEqual(s.rimOpacity, 0, accuracy: 0.001)
        XCTAssertTrue(s.barOpacities.allSatisfy { $0 == 0 })
    }

    func test_atSpawnEnd_figuresAreFullySizedAtSeedPosition() {
        let s = SpawnTimeline.state(at: 0.167)
        XCTAssertEqual(s.figureOpacity, 1, accuracy: 0.01)
        XCTAssertEqual(s.figureScale, 1.0, accuracy: 0.01)
        XCTAssertEqual(s.pillWidth, 45, accuracy: 0.5)  // still seed
        XCTAssertEqual(s.triangleX, 3.5, accuracy: 0.5)
        XCTAssertEqual(s.dotX, 25, accuracy: 0.5)
    }

    // MARK: - Anticipation (0.167 → 0.236)

    func test_atAnticipationEnd_pillCompresses_figuresLeanInward() {
        let s = SpawnTimeline.state(at: 0.236)
        XCTAssertEqual(s.figureScale, 0.97, accuracy: 0.01)
        XCTAssertEqual(s.pillWidth, 42, accuracy: 0.5)
        XCTAssertEqual(s.triangleX, 5, accuracy: 0.5)
        XCTAssertEqual(s.dotX, 23.5, accuracy: 0.5)
    }

    // MARK: - Push (0.236 → 0.472)

    func test_atPushEnd_pillIsFullWidth_figuresAtExtremes() {
        let s = SpawnTimeline.state(at: 0.472)
        XCTAssertEqual(s.figureScale, 1.0, accuracy: 0.01)
        XCTAssertEqual(s.pillWidth, 170, accuracy: 0.5)
        XCTAssertEqual(s.triangleX, 12, accuracy: 0.5)
        XCTAssertEqual(s.dotX, 135, accuracy: 0.5)
        XCTAssertTrue(s.barOpacities.allSatisfy { $0 == 0 }, "no bars during push")
        XCTAssertEqual(s.rimOpacity, 0, accuracy: 0.01)
    }

    // MARK: - Hold (0.472 → 0.556)

    func test_duringHold_circleStaysAtFarRight_noBarsYet() {
        let s = SpawnTimeline.state(at: 0.51)
        XCTAssertEqual(s.dotX, 135, accuracy: 0.5)
        XCTAssertTrue(s.barOpacities.allSatisfy { $0 == 0 })
        XCTAssertEqual(s.rimOpacity, 0, accuracy: 0.01)
    }

    // MARK: - Traverse (0.556 → 0.833)

    func test_atTraverseStart_circleBeginsLeftward_noBarsRevealedYet() {
        let s = SpawnTimeline.state(at: 0.556)
        XCTAssertEqual(s.dotX, 135, accuracy: 0.5)
        XCTAssertEqual(s.barOpacities[4], 0, accuracy: 0.01)
    }

    func test_atTraverseEnd_circleAtFinalPosition_allBarsVisible() {
        let s = SpawnTimeline.state(at: 0.833)
        XCTAssertEqual(s.dotX, 46, accuracy: 0.5)
        // Bars cascade right-to-left during traverse — bar 5 (rightmost) reveals
        // first, bar 1 (leftmost) reveals last. By traverse end all should be
        // fully visible.
        for (i, opacity) in s.barOpacities.enumerated() {
            XCTAssertEqual(opacity, 1, accuracy: 0.05, "bar \(i) should be visible at traverse end")
        }
    }

    func test_barsRevealRightToLeft_duringTraverse() {
        // Mid-traverse: rightmost bars should be more visible than leftmost.
        let s = SpawnTimeline.state(at: 0.7)
        XCTAssertGreaterThan(s.barOpacities[4], s.barOpacities[0],
                             "rightmost bar should reveal earlier than leftmost during the right-to-left cascade")
    }

    // MARK: - Ignite (0.847 → 1.0)

    func test_atIgniteStart_rimBeginsToFadeIn() {
        // Sample 3ms past the exact phase boundary so we observe a visible
        // fade-in (the rim curve correctly returns 0 AT the boundary itself).
        let s = SpawnTimeline.state(at: 0.85)
        XCTAssertGreaterThan(s.rimOpacity, 0)
        XCTAssertLessThan(s.rimOpacity, 0.5)
    }

    func test_atIgniteStartExactly_rimIsZero() {
        // At the exact phase boundary, rim has not yet started fading in.
        // The first observable opacity comes a few normalised ticks later
        // (covered by test_atIgniteStart_rimBeginsToFadeIn).
        let s = SpawnTimeline.state(at: 0.847)
        XCTAssertEqual(s.rimOpacity, 0, accuracy: 0.0001)
    }

    func test_atTimeOne_rimFullyVisible_allBarsVisible() {
        let s = SpawnTimeline.state(at: 1.0)
        XCTAssertEqual(s.rimOpacity, 1, accuracy: 0.01)
        XCTAssertTrue(s.barOpacities.allSatisfy { $0 >= 0.99 })
    }

    // MARK: - Boundary safety

    func test_progressAboveOne_clampsToFinalState() {
        let s = SpawnTimeline.state(at: 1.5)
        XCTAssertEqual(s.rimOpacity, 1, accuracy: 0.01)
        XCTAssertEqual(s.dotX, 46, accuracy: 0.5)
    }

    func test_negativeProgress_clampsToInitialState() {
        let s = SpawnTimeline.state(at: -0.2)
        XCTAssertEqual(s.figureOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(s.pillWidth, 45, accuracy: 0.001)
    }
}
