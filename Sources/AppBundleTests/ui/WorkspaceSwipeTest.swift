@testable import AppBundle
import AppKit
import XCTest

final class WorkspaceSwipeTest: XCTestCase {
    func testPreviewTracksProgressIncludingReversalAndBounds() {
        for progress in [0.0, 0.25, 0.5, 1, 0.6, 0.2, 0] {
            XCTAssertEqual(WorkspaceSwipePreviewGeometry.trackingProgress(progress), progress)
        }
        XCTAssertEqual(WorkspaceSwipePreviewGeometry.trackingProgress(-1), 0)
        XCTAssertEqual(WorkspaceSwipePreviewGeometry.trackingProgress(2), 1)
        XCTAssertEqual(WorkspaceSwipePreviewGeometry.trackingProgress(.nan), 0)
    }

    func testPreviewOffsetsMeetWithoutGapInBothDirections() {
        for incomingFromBelow in [false, true] {
            for progress in [0.0, 0.25, 0.5, 1.0] {
                let offsets = WorkspaceSwipePreviewGeometry.offsets(height: 1080, progress: progress, incomingFromBelow: incomingFromBelow)
                XCTAssertEqual(abs(offsets.incoming - offsets.outgoing), 1080)
                XCTAssertEqual(abs(offsets.outgoing), 1080 * progress)
            }
        }
    }

    func testTheNextWorkspaceRisesFromBelowLikeTheSidebar() {
        // Layer space is y-up: the current workspace leaves upward and the next one comes from below.
        let next = WorkspaceSwipePreviewGeometry.offsets(height: 1080, progress: 0.25, incomingFromBelow: true)
        XCTAssertEqual(next.outgoing, 270)
        XCTAssertEqual(next.incoming, 270 - 1080)
        let previous = WorkspaceSwipePreviewGeometry.offsets(height: 1080, progress: 0.25, incomingFromBelow: false)
        XCTAssertEqual(previous.outgoing, -270)
        XCTAssertEqual(previous.incoming, -270 + 1080)
        XCTAssertEqual(WorkspaceSwipePreviewGeometry.settlingAnimation(from: 0, to: 1, speed: 0, duration: 0.2).keyPath,
                       "transform.translation.y")
    }
}
