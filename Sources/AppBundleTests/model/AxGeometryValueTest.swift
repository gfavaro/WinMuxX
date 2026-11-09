@testable import AppBundle
import AppKit
import XCTest

final class AxGeometryValueTest: XCTestCase {
    func testGeometryIsReadOnlyFromAValueOfItsOwnType() throws {
        var size = CGSize(width: 640, height: 480)
        var point = CGPoint(x: 12, y: 34)
        let sizeValue = try XCTUnwrap(AXValueCreate(.cgSize, &size))
        let pointValue = try XCTUnwrap(AXValueCreate(.cgPoint, &point))

        XCTAssertEqual(Ax.sizeAttr.getter(sizeValue), size)
        XCTAssertEqual(Ax.topLeftCornerAttr.getter(pointValue), point)
        // The app chooses what it answers with. Another type is no geometry, and must not stop WinMuxX.
        XCTAssertNil(Ax.sizeAttr.getter(pointValue))
        XCTAssertNil(Ax.topLeftCornerAttr.getter(sizeValue))
        XCTAssertNil(Ax.sizeAttr.getter("640x480" as NSString))
        XCTAssertNil(Ax.topLeftCornerAttr.getter(NSNumber(value: 1)))
    }
}
