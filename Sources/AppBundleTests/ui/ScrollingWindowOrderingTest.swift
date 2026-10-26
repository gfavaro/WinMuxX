@testable import AppBundle
import AppKit
import XCTest

final class ScrollingWindowOrderingTest: XCTestCase {
    func testAlreadyOrderedAndNonoverlappingTilesNeedNoRaises() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let overlapped = [ScrollingStackItem(id: 1, frame: frame), .init(id: 2, frame: frame)]
        XCTAssertEqual(scrollingWindowRaises(desired: overlapped, currentFrontToBack: [2, 1]), [])
        let tiles = [ScrollingStackItem(id: 1, frame: frame), .init(id: 2, frame: frame.offsetBy(dx: 110, dy: 0))]
        XCTAssertEqual(scrollingWindowRaises(desired: tiles, currentFrontToBack: [1, 2]), [])
    }

    func testConcealedColumnsArePlacedBelowVisibleColumnsWithMinimalRaises() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let desired = [ScrollingStackItem(id: 1, frame: frame), .init(id: 2, frame: frame), .init(id: 3, frame: frame)]
        XCTAssertEqual(scrollingWindowRaises(desired: desired, currentFrontToBack: [1, 2, 3]), [2, 3])
        XCTAssertEqual(scrollingWindowRaises(desired: desired, currentFrontToBack: [2, 1, 3]), [3])
        XCTAssertEqual(scrollingWindowRaises(desired: [], currentFrontToBack: [1, 2]), [])
    }
}
