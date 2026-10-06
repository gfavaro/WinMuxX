@testable import AppBundle
import AppKit
import XCTest

final class DestroyedWindowElementTest: XCTestCase {
    func testStaleDiscoveryCannotResurrectDestroyedElement() {
        let old = AXUIElementCreateApplication(12345)
        let staleCopy = AXUIElementCreateApplication(12345)
        XCTAssertTrue(isDestroyedWindowElement(old, staleCopy))
    }

    func testDifferentElementCanBeRegistered() {
        XCTAssertFalse(isDestroyedWindowElement(
            AXUIElementCreateApplication(12345), AXUIElementCreateApplication(12346)
        ))
    }

    func testFirstDiscoveryIsNotSuppressed() {
        XCTAssertFalse(isDestroyedWindowElement(nil, AXUIElementCreateApplication(12345)))
    }
}
