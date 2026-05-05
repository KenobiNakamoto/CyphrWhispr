import XCTest
@testable import CyphrWhispr

final class InstallTimelineTests: XCTestCase {

    // MARK: - Intro

    func testIntro_atZero_pillIsSeed_figuresInvisible() {
        let s = InstallTimeline.introState(at: 0)
        XCTAssertEqual(s.pillWidth, InstallTimeline.pillSeedW)
        XCTAssertEqual(s.figureOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(s.figureScale, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.triangleX, InstallTimeline.triPinnedX)
        XCTAssertEqual(s.dotX, InstallTimeline.pillSeedW - 29, accuracy: 0.001)
        XCTAssertEqual(s.labelOpacity, 0, accuracy: 0.001)
    }

    func testIntro_atSpawnEnd_figuresFullyVisible() {
        let s = InstallTimeline.introState(at: InstallTimeline.pSpawnEnd)
        XCTAssertEqual(s.figureOpacity, 1, accuracy: 0.01)
        XCTAssertEqual(s.figureScale, 1.0, accuracy: 0.01)
        XCTAssertEqual(s.pillWidth, InstallTimeline.pillSeedW, accuracy: 0.5)
    }

    func testIntro_atAnticipationEnd_pillCompressed() {
        let s = InstallTimeline.introState(at: InstallTimeline.pAnticipationEnd)
        XCTAssertEqual(s.pillWidth, InstallTimeline.pillAntiW, accuracy: 0.5)
        XCTAssertEqual(s.figureScale, 0.97, accuracy: 0.01)
    }

    func testIntro_atPushEnd_pillFullWidth_figuresAtExtremes() {
        let s = InstallTimeline.introState(at: InstallTimeline.pPushEnd)
        XCTAssertEqual(s.pillWidth, InstallTimeline.pillFullW, accuracy: 0.5)
        XCTAssertEqual(s.triangleX, InstallTimeline.triPinnedX)
        XCTAssertEqual(s.dotX, InstallTimeline.dotPushEndX, accuracy: 0.5)
    }

    func testIntro_atOne_labelFullyVisible_atFinalY() {
        let s = InstallTimeline.introState(at: 1.0)
        XCTAssertEqual(s.labelOpacity, 1.0, accuracy: 0.001)
        XCTAssertEqual(s.labelOffsetY, 0, accuracy: 0.5)
    }

    func testIntro_clampsBelowZero() {
        let s = InstallTimeline.introState(at: -1)
        XCTAssertEqual(s.figureOpacity, 0, accuracy: 0.001)
    }

    func testIntro_clampsAboveOne() {
        let s = InstallTimeline.introState(at: 99)
        XCTAssertEqual(s.labelOpacity, 1.0, accuracy: 0.001)
    }

    // MARK: - Outro

    func testOutro_atZero_circleAtPushEnd_rimVisible_barsHidden() {
        let s = InstallTimeline.outroState(at: 0)
        XCTAssertEqual(s.dotX, InstallTimeline.dotPushEndX, accuracy: 0.5)
        XCTAssertEqual(s.triangleX, InstallTimeline.triPinnedX, accuracy: 0.5)
        XCTAssertEqual(s.rimOpacity, 1.0, accuracy: 0.001)
        XCTAssertEqual(s.labelOpacity, 1.0, accuracy: 0.001)
        for i in 0..<7 {
            XCTAssertEqual(s.barOpacities[i], 0, accuracy: 0.001)
        }
        XCTAssertEqual(s.cometOpacity, 0, accuracy: 0.001)
    }

    func testOutro_atOne_circleAtIdle_barsVisible_cometIgnited() {
        let s = InstallTimeline.outroState(at: 1.0)
        XCTAssertEqual(s.dotX, InstallTimeline.dotIdleX, accuracy: 0.5)
        XCTAssertEqual(s.triangleX, InstallTimeline.triIdleX, accuracy: 0.5)
        XCTAssertEqual(s.rimOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(s.labelOpacity, 0, accuracy: 0.001)
        for i in 0..<7 {
            XCTAssertEqual(s.barOpacities[i], 1, accuracy: 0.01)
        }
        XCTAssertEqual(s.cometOpacity, 1, accuracy: 0.01)
        XCTAssertEqual(s.staticRimOpacity, 1, accuracy: 0.01)
    }

    func testOutro_barCascadeIsRightToLeft() {
        // Mid-cascade: rightmost bars should be more visible than leftmost
        let s = InstallTimeline.outroState(at: 0.4)
        XCTAssertGreaterThan(s.barOpacities[6], s.barOpacities[0])
        XCTAssertGreaterThanOrEqual(s.barOpacities[5], s.barOpacities[0])
    }

    func testOutro_rimFadesOutByPRimFadeEnd() {
        let s = InstallTimeline.outroState(at: InstallTimeline.pRimFadeEnd)
        XCTAssertEqual(s.rimOpacity, 0, accuracy: 0.01)
    }

    func testOutro_cometStaysOffBeforeIgniteStart() {
        let s = InstallTimeline.outroState(at: InstallTimeline.pCometIgniteStart - 0.01)
        XCTAssertEqual(s.cometOpacity, 0, accuracy: 0.001)
    }

    func testOutro_clampsAboveOne() {
        let s = InstallTimeline.outroState(at: 99)
        XCTAssertEqual(s.dotX, InstallTimeline.dotIdleX, accuracy: 0.5)
    }

    // MARK: - Geometry constants

    func testGeometry_barIdleColumnsMatchSpawnTimeline() {
        XCTAssertEqual(InstallTimeline.barIdleColumns, SpawnTimeline.barColumns)
    }

    func testGeometry_barIdleHeightsMatchSpawnTimeline() {
        XCTAssertEqual(InstallTimeline.barIdleHeights, SpawnTimeline.barHeights)
    }

    func testGeometry_dotIdleX_matchesSpawnDotTraverseEnd() {
        XCTAssertEqual(InstallTimeline.dotIdleX, SpawnTimeline.dotTraverseEndX)
    }
}
