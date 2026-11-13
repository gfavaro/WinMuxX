@testable import AppBundle
import XCTest

final class AXTimeoutProcessOwnershipTest: XCTestCase {
    func testUnresponsiveRunningProcessKeepsItsExistingWindows() {
        XCTAssertTrue(MacApp.shouldPreserveWindowOnAXTimeout(
            sameProcess: true, appRetired: false, appTerminated: false))
    }

    func testReusedPIDDoesNotPreserveWindowsFromPreviousProcess() {
        XCTAssertFalse(MacApp.shouldPreserveWindowOnAXTimeout(
            sameProcess: false, appRetired: false, appTerminated: false))
    }

    func testRetiredOrTerminatedAppDoesNotSurviveTimeoutFallback() {
        XCTAssertFalse(MacApp.shouldPreserveWindowOnAXTimeout(
            sameProcess: true, appRetired: true, appTerminated: false))
        XCTAssertFalse(MacApp.shouldPreserveWindowOnAXTimeout(
            sameProcess: true, appRetired: false, appTerminated: true))
    }
}
