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
        for slidesLeft in [false, true] {
            for progress in [0.0, 0.25, 0.5, 1.0] {
                let offsets = WorkspaceSwipePreviewGeometry.offsets(width: 1920, progress: progress, slidesLeft: slidesLeft)
                XCTAssertEqual(abs(offsets.incoming - offsets.outgoing), 1920)
                XCTAssertEqual(abs(offsets.outgoing), 1920 * progress)
            }
        }
    }
}
