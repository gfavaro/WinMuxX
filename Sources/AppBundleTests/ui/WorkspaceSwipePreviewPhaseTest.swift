@testable import AppBundle
import XCTest

final class WorkspaceSwipePreviewPhaseTest: XCTestCase {
    func testReleaseDuringPreparationCannotReviveWhenImageArrives() {
        for commit in [false, true] {
            var phase = WorkspaceSwipePreviewPhase.preparing
            XCTAssertFalse(phase.isSettling)
            phase.settle(commit: commit)
            phase.imageReady()
            XCTAssertEqual(phase, .idle)
        }
    }

    func testImageReadinessStartsTrackingOnlyDuringPreparation() {
        var phase = WorkspaceSwipePreviewPhase.preparing
        phase.imageReady()
        XCTAssertEqual(phase, .tracking)
        phase.settle(commit: true)
        phase.imageReady()
        XCTAssertEqual(phase, .waitingForAnimationAndWorkspace)
    }

    func testCommitKeepsOverlayUntilAnimationAndWorkspaceAreBothReady() {
        for workspaceFirst in [false, true] {
            var phase = WorkspaceSwipePreviewPhase.tracking
            phase.settle(commit: true)
            XCTAssertTrue(phase.isSettling)
            if workspaceFirst { phase.workspaceReady() } else { phase.animationFinished() }
            XCTAssertNotEqual(phase, .idle)
            if workspaceFirst { phase.animationFinished() } else { phase.workspaceReady() }
            XCTAssertEqual(phase, .idle)
            XCTAssertFalse(phase.isSettling)
        }
    }

    func testCancelledGestureWaitsOnlyForItsReturnAnimation() {
        var phase = WorkspaceSwipePreviewPhase.tracking
        phase.settle(commit: false)
        phase.workspaceReady()
        XCTAssertTrue(phase.isSettling)
        phase.animationFinished()
        XCTAssertEqual(phase, .idle)
    }

    func testRepeatedReleaseOrCompletionCannotRestartOrPrematurelyCloseOverlay() {
        var phase = WorkspaceSwipePreviewPhase.tracking
        phase.settle(commit: true)
        phase.animationFinished()
        phase.animationFinished()
        phase.settle(commit: false)
        XCTAssertEqual(phase, .waitingForWorkspace)
        phase.workspaceReady()
        phase.workspaceReady()
        XCTAssertEqual(phase, .idle)
    }

    func testLateCompletionsAfterCancellationDoNotReviveOverlay() {
        var phase = WorkspaceSwipePreviewPhase.tracking
        phase.settle(commit: true)
        phase = .idle
        phase.animationFinished()
        phase.workspaceReady()
        phase.settle(commit: true)
        XCTAssertEqual(phase, .idle)
    }

    func testUnrelatedCompletionsDoNotInterruptFingerTracking() {
        var phase = WorkspaceSwipePreviewPhase.tracking
        phase.workspaceReady()
        phase.animationFinished()
        XCTAssertEqual(phase, .tracking)
        XCTAssertFalse(phase.isSettling)
    }
}
