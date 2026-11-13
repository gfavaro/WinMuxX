@testable import AppBundle
import Foundation
import XCTest

final class WindowRegistrationIdentityTest: XCTestCase {
    func testCleanupMayOnlyModifyItsOwnRegisteredWindow() {
        let current = NSObject()
        let previous = NSObject()
        XCTAssertTrue(isCurrentWindowRegistration(current, candidate: current))
        XCTAssertFalse(isCurrentWindowRegistration(current, candidate: previous))
    }

    func testUnregisteredWindowCannotClearReplacementState() {
        let stale = NSObject()
        XCTAssertFalse(isCurrentWindowRegistration(nil, candidate: stale))
    }
}
