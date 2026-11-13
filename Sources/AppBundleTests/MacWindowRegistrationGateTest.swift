@testable import AppBundle
import XCTest

final class MacWindowRegistrationGateTest: XCTestCase {
    func testLiveWindowFromRunningAppMayCommit() {
        XCTAssertTrue(canCommitWindowRegistration(windowStillExists: true, appTerminated: false))
    }

    func testWindowClosedDuringAXDiscoveryCannotCommit() {
        XCTAssertFalse(canCommitWindowRegistration(windowStillExists: false, appTerminated: false),
                       "The WindowServer check must be repeated after asynchronous discovery")
    }

    func testTerminatedAppCannotCommitEvenIfWindowIDWasReused() {
        XCTAssertFalse(canCommitWindowRegistration(windowStillExists: true, appTerminated: true))
    }

    func testClosedWindowFromTerminatedAppCannotCommit() {
        XCTAssertFalse(canCommitWindowRegistration(windowStillExists: false, appTerminated: true))
    }
}
