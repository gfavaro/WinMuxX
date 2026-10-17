@testable import AppBundle
import XCTest
import AppKit

final class WorkspaceWindowRevealTest: XCTestCase {
    func testWindowThatReappearedOnScreenIsNotConfirmedParked() {
        let parking = CGPoint(x: 1709, y: 1111)
        XCTAssertTrue(workspaceParkingPositionMatches(parking, parking))
        XCTAssertTrue(workspaceParkingPositionMatches(CGPoint(x: 1708, y: 1110), parking))
        XCTAssertFalse(workspaceParkingPositionMatches(CGPoint(x: 48, y: 43), parking),
                       "Safari must be parked again even if its old hidden flag is still set")
        XCTAssertFalse(workspaceParkingPositionMatches(CGPoint(x: 1709, y: 43), parking))
    }

    func testFailureKeepsWindowParkedForRetry() {
        var state = WorkspaceWindowRevealState()
        state.park()
        let first = state.begin()
        XCTAssertEqual(state.phase, .restoring)
        XCTAssertFalse(state.finish(first, succeeded: false))
        XCTAssertEqual(state.phase, .parked)
        let retry = state.begin()
        XCTAssertTrue(state.finish(retry, succeeded: true))
        XCTAssertEqual(state.phase, .visible)
    }

    func testOutgoingTransitionInvalidatesAnOlderReveal() {
        var state = WorkspaceWindowRevealState()
        state.park()
        let old = state.begin()
        state.park()
        XCTAssertFalse(state.finish(old, succeeded: true))
        XCTAssertEqual(state.phase, .parked)
    }

    func testOldCompletionCannotPublishOrCancelANewerRestore() {
        var state = WorkspaceWindowRevealState()
        state.park()
        let old = state.begin()
        let current = state.begin()
        XCTAssertFalse(state.finish(old, succeeded: true))
        XCTAssertFalse(state.finish(old, succeeded: false))
        XCTAssertEqual(state.phase, .restoring)
        XCTAssertTrue(state.finish(current, succeeded: true))
        XCTAssertFalse(state.finish(current, succeeded: false))
        XCTAssertEqual(state.phase, .visible)
    }
}
