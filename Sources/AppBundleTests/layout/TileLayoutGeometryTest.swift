@testable import AppBundle
import XCTest

final class TileLayoutGeometryTest: XCTestCase {
    func testTwoHorizontalTilesIncludePhysicalGapAndShareVirtualExtent() {
        let input = TileLayoutInput(origin: CGPoint(x: -100, y: 20), size: CGSize(width: 1000, height: 700),
            horizontal: true, innerGap: 20, weights: [500, 500], minimumExtents: [0, 0], master: false, reversed: false)
        let frames = TileLayoutGeometry.calculate(input)
        XCTAssertEqual(frames.map(\.weight), [500, 500])
        XCTAssertEqual(frames[0].physical, CGRect(x: -100, y: 20, width: 490, height: 700))
        XCTAssertEqual(frames[1].physical, CGRect(x: 410, y: 20, width: 490, height: 700))
        XCTAssertEqual(frames[0].virtual.maxX, frames[1].virtual.minX)
        XCTAssertEqual(input.weights, [500, 500], "calculation must not mutate its input")
    }

    func testMasterReversalMirrorsPhysicalAndVirtualFrames() {
        let normal = TileLayoutGeometry.calculate(TileLayoutInput(origin: .zero, size: CGSize(width: 900, height: 600),
            horizontal: true, innerGap: 0, weights: [600, 300], minimumExtents: [0, 0], master: true, reversed: false))
        let reversed = TileLayoutGeometry.calculate(TileLayoutInput(origin: .zero, size: CGSize(width: 900, height: 600),
            horizontal: true, innerGap: 0, weights: [600, 300], minimumExtents: [0, 0], master: true, reversed: true))
        XCTAssertEqual(reversed[0].physical.minX, 300)
        XCTAssertEqual(reversed[1].physical.minX, 0)
        XCTAssertEqual(reversed[0].weight, normal[0].weight)
    }

    func testMinimumsFitAndImpossibleFitKeepsRequestedSizes() {
        XCTAssertEqual(TileLayoutGeometry.fit([30, 70], minimums: [50, 20], total: 100), [50, 50])
        XCTAssertEqual(TileLayoutGeometry.fit([30, 70], minimums: [80, 40], total: 100), [30, 70])
    }

    func testEmptyAndMismatchedInputsReturnNoFrames() {
        XCTAssertTrue(TileLayoutGeometry.calculate(TileLayoutInput(origin: .zero, size: .zero,
            horizontal: false, innerGap: 0, weights: [], minimumExtents: [], master: false, reversed: false)).isEmpty)
        XCTAssertTrue(TileLayoutGeometry.calculate(TileLayoutInput(origin: .zero, size: .zero,
            horizontal: false, innerGap: 0, weights: [1], minimumExtents: [], master: false, reversed: false)).isEmpty)
    }
}
