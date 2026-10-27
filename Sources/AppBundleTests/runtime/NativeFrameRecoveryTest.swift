@testable import AppBundle
import XCTest

final class NativeFrameRecoveryTest: XCTestCase {
    private let tile = Rect(topLeftX: 100, topLeftY: 50, width: 800, height: 600)

    func testRestingAllowsLargerWindowsAndRowSizedOnes() {
        XCTAssertTrue(windowRestsOnTile(CGRect(x: 100, y: 50, width: 800, height: 600), tile: tile))
        XCTAssertTrue(windowRestsOnTile(CGRect(x: 101, y: 52, width: 950, height: 600), tile: tile), "Cannot shrink to the tile")
        XCTAssertTrue(windowRestsOnTile(CGRect(x: 100, y: 50, width: 790, height: 584), tile: tile), "Whole rows and columns")
        XCTAssertFalse(windowRestsOnTile(CGRect(x: 300, y: 50, width: 800, height: 600), tile: tile), "Moved")
        XCTAssertFalse(windowRestsOnTile(CGRect(x: 100, y: 50, width: 500, height: 600), tile: tile), "Shrunk")
    }

    func testBudgetStopsAFightAndRefillsOnRestOrANewTile() {
        var budget = FrameRecoveryBudget()
        XCTAssertEqual((0..<5).map { _ in budget.shouldReapply(tile: tile, resting: false) }, [true, true, true, false, false],
                       "An app that keeps moving its window is left alone after three tries")
        XCTAssertFalse(budget.shouldReapply(tile: tile, resting: true))
        XCTAssertTrue(budget.shouldReapply(tile: tile, resting: false), "Resting refills it")
        var moved = tile
        moved.topLeftX += 400
        _ = budget.shouldReapply(tile: tile, resting: false)
        _ = budget.shouldReapply(tile: tile, resting: false)
        XCTAssertTrue(budget.shouldReapply(tile: moved, resting: false), "A new tile refills it")
    }
}
