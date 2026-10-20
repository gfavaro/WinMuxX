@testable import AppBundle
import XCTest
import AppKit

final class WorkspaceWindowRevealTest: XCTestCase {
    func testWindowThatReappearedOnScreenIsNotConfirmedParked() {
        let parking = CGPoint(x: 1709, y: 1111)
        let display = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        func acceptable(_ x: CGFloat, _ y: CGFloat) -> Bool {
            workspaceParkingFrameIsAcceptable(CGRect(x: x, y: y, width: 1659, height: 1074),
                requested: parking, displays: [display])
        }
        XCTAssertTrue(acceptable(1709, 1111))
        XCTAssertTrue(acceptable(1709, 1080), "Native titlebar clamping must not start a parking retry loop")
        XCTAssertFalse(acceptable(48, 43),
                       "Safari must be parked again even if its old hidden flag is still set")
        XCTAssertFalse(acceptable(1709, 43), "A window moving far up the edge must still be repaired")
        XCTAssertFalse(acceptable(1678, 1080), "A visible 32-by-32 corner is not the one-point parking strip")
    }

    func testParkingClampMustRemainHiddenOnEveryDisplay() {
        let observed = CGRect(x: 1709, y: 1080, width: 1659, height: 1074)
        let main = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let right = CGRect(x: 1710, y: 0, width: 1920, height: 1112)
        XCTAssertFalse(workspaceParkingFrameIsAcceptable(observed, requested: CGPoint(x: 1709, y: 1111), displays: [main, right]))
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1112)
        XCTAssertTrue(workspaceParkingFrameIsAcceptable(CGRect(x: -2619, y: 880, width: 700, height: 500),
            requested: CGPoint(x: -2619, y: 911), displays: [left, main]))
    }

    func testInvalidOrUnknownParkingGeometryIsNeverAccepted() {
        let display = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let parking = CGPoint(x: 1709, y: 1111)
        for rect in [CGRect.zero, CGRect(x: CGFloat.nan, y: 1080, width: 800, height: 600),
                     CGRect(x: 1709, y: 1080, width: CGFloat.infinity, height: 600)] {
            XCTAssertFalse(workspaceParkingFrameIsAcceptable(rect, requested: parking, displays: [display]))
        }
        XCTAssertFalse(workspaceParkingFrameIsAcceptable(CGRect(x: 1709, y: 1080, width: 800, height: 600),
            requested: parking, displays: []))
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
