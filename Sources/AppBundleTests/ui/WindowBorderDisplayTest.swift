@testable import AppBundle
import XCTest

final class WindowBorderDisplayTest: XCTestCase {
    func testABorderCrossingADisplayEdgeIsPulledOntoTheDisplay() {
        // The external display ends at y = 0; a window reaching y = -2 with a 4 pt border
        // would put its bottom edge 2 pt past it.
        let display = CGRect(x: -908, y: -1440, width: 3440, height: 1440)
        let window = CGRect(x: 814, y: -1408, width: 1716, height: 1406)
        let frame = windowBorderFrame(window, width: 4, within: display)
        XCTAssertTrue(display.contains(frame.insetBy(dx: -4, dy: -4)), "The whole border is on the display")
        XCTAssertEqual(frame.minY, window.minY, "Edges inside the display are untouched")
        XCTAssertEqual(frame.minX, window.minX)
        XCTAssertEqual(frame.maxX, display.maxX - 4, "The right edge also reached past it")
        // A window well inside its display keeps its exact frame.
        let inside = CGRect(x: 100, y: -1300, width: 800, height: 600)
        XCTAssertEqual(windowBorderFrame(inside, width: 4, within: display), inside)
        XCTAssertEqual(windowBorderFrame(window, width: 4, within: nil), window)
    }
}
