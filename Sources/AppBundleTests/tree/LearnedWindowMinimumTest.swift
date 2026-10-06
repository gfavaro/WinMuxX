@testable import AppBundle
import AppKit
import XCTest

final class LearnedWindowMinimumTest: XCTestCase {
    func testFullscreenMinimizedAndIntermediateAnimationFramesAreNotEvidence() {
        XCTAssertTrue(shouldLearnWindowMinimum(nativeFullscreen: false, nativeMinimized: false, animating: false))
        XCTAssertFalse(shouldLearnWindowMinimum(nativeFullscreen: true, nativeMinimized: false, animating: false))
        XCTAssertFalse(shouldLearnWindowMinimum(nativeFullscreen: false, nativeMinimized: true, animating: false))
        XCTAssertFalse(shouldLearnWindowMinimum(nativeFullscreen: false, nativeMinimized: false, animating: true))
    }

    func testConfirmedRefusalLearnsEachAxisIndependently() {
        var minimum = LearnedWindowMinimum()
        minimum.observe(requested: CGSize(width: 200, height: 300),
                        first: CGSize(width: 400, height: 300),
                        confirmed: CGSize(width: 400, height: 300))
        XCTAssertEqual(minimum.size, CGSize(width: 400, height: 0))
    }

    func testDelayedResizeAndCellRoundingDoNotBecomeMinima() {
        var minimum = LearnedWindowMinimum()
        minimum.observe(requested: CGSize(width: 200, height: 200),
                        first: CGSize(width: 400, height: 400),
                        confirmed: CGSize(width: 200, height: 200))
        minimum.observe(requested: CGSize(width: 200, height: 200),
                        first: CGSize(width: 210, height: 218),
                        confirmed: CGSize(width: 210, height: 218))
        XCTAssertTrue(minimum.isEmpty)
    }

    func testSuccessfulSmallerResizeInvalidatesEarlierEvidence() {
        var minimum = LearnedWindowMinimum()
        minimum.observe(requested: CGSize(width: 200, height: 200),
                        first: CGSize(width: 400, height: 400),
                        confirmed: CGSize(width: 400, height: 400))
        minimum.observe(requested: CGSize(width: 300, height: 300),
                        first: CGSize(width: 300, height: 300),
                        confirmed: CGSize(width: 300, height: 300))
        XCTAssertTrue(minimum.isEmpty)
    }

    func testInvalidGeometryIsIgnoredAndWindowsDoNotShareLimits() {
        var first = LearnedWindowMinimum()
        let second = LearnedWindowMinimum()
        first.observe(requested: CGSize(width: 200, height: 200),
                      first: CGSize(width: 400, height: 400),
                      confirmed: CGSize(width: 400, height: 400))
        XCTAssertTrue(second.isEmpty)
        first.observe(requested: CGSize(width: CGFloat.nan, height: 200),
                      first: CGSize(width: 900, height: 900),
                      confirmed: CGSize(width: 900, height: 900))
        XCTAssertEqual(first.size, CGSize(width: 400, height: 400))
    }
}
