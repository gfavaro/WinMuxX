@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class LayoutMinimumFitTest: XCTestCase {
    func testRaisesShortWindowsAndTakesSpaceFromRemainingSiblings() {
        let result = fitLayoutSizes([300, 300, 300], minimums: [450, 0, 0], total: 900)

        XCTAssertEqual(result[0], 450, accuracy: 0.001)
        XCTAssertEqual(result[1] + result[2], 450, accuracy: 0.001)
        XCTAssertEqual(result.reduce(0, +), 900, accuracy: 0.001)
    }

    func testPinsMultipleMinimumsProportionally() {
        let result = fitLayoutSizes([100, 100, 100], minimums: [200, 250, 0], total: 600)

        XCTAssertEqual(result[0], 200, accuracy: 0.001)
        XCTAssertEqual(result[1], 250, accuracy: 0.001)
        XCTAssertEqual(result[2], 150, accuracy: 0.001)
    }

    func testOverflowKeepsRequestedDistribution() {
        let requested: [CGFloat] = [300, 300, 300]
        XCTAssertEqual(fitLayoutSizes(requested, minimums: [400, 400, 400], total: 900), requested)
    }

    func testNoMinimumsKeepRequestedDistribution() {
        let requested: [CGFloat] = [120, 280, 500]
        XCTAssertEqual(fitLayoutSizes(requested, minimums: [0, 0, 0], total: 900), requested)
    }
}
