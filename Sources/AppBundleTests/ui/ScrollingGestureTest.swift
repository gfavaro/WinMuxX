@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class ScrollingGestureTest: WorkspaceTestCase {
    private func fixture() -> (Workspace, [TestWindow]) {
        let workspace = focus.workspace
        workspace.rootTilingContainer.layout = .tiles
        let windows = (0..<4).map { TestWindow.new(id: UInt32(98000 + $0), parent: workspace.rootTilingContainer) }
        windows.forEach { $0.scrollingColumnWidth = 0.7 }
        workspace.transitionArrangement(to: .scrolling)
        _ = windows[0].focusWindow()
        return (workspace, windows)
    }

    private func frame(_ x: Double, time: Double, fingers: Int = 3, device: UInt64 = 1) -> WorkspaceTouchFrame {
        .init(device: device, fingers: fingers, x: x, y: 0.5, timestamp: time, contacts: 123)
    }

    private func feed(_ controller: WorkspaceScrollingGestureController, _ workspace: Workspace,
                      _ frames: [WorkspaceTouchFrame], epoch: UInt64? = nil, offset: CGFloat? = nil) {
        controller.handle(frames, capturedWorkspace: workspace,
            capturedMonitorPoint: workspace.workspaceMonitor.rect.topLeftCorner,
            capturedOffset: offset ?? workspace.scrollingOffset, capturedTopology: workspace.scrollingTopologySignature,
            capturedEpoch: epoch ?? workspace.scrollingSessionEpoch)
    }

    func testEndClampReversesImmediatelyAndTrackingPreservesFocus() async throws {
        let (workspace, windows) = fixture()
        let controller = WorkspaceScrollingGestureController(dependencies: .init(eligible: { true }, reduceMotion: { true }))
        defer { controller.reset() }
        feed(controller, workspace, [frame(0.5, time: 1), frame(0.05, time: 1.01)])
        XCTAssertEqual(workspace.scrollingOffset, workspace.scrollingMetrics.offsetRange.upperBound, accuracy: 0.01)
        let end = workspace.scrollingOffset
        feed(controller, workspace, [frame(0.06, time: 1.02)])
        XCTAssertLessThan(workspace.scrollingOffset, end, "Reversal consumes the new delta immediately, with no stored overshoot")
        XCTAssertTrue(focus.windowOrNil === windows[0])
        XCTAssertTrue(workspace.scrollingGestureMotionActive)
        let trackedOffset = workspace.scrollingOffset
        workspace.lastScrollingFocusWindowId = windows[3].windowId
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.scrollingOffset, trackedOffset, accuracy: 0.01,
                       "Refresh cannot reveal the previous focus while a gesture owns the viewport")
    }

    func testReverseDirectionAndInvalidContactRestoresStartingOffset() {
        let (workspace, windows) = fixture()
        config.workspaceSwipe.reverseDirection = true
        workspace.scrollingOffset = workspace.scrollingMetrics.offsetRange.upperBound / 2
        let start = workspace.scrollingOffset
        let controller = WorkspaceScrollingGestureController(dependencies: .init(eligible: { true }, reduceMotion: { true }))
        defer { controller.reset() }
        feed(controller, workspace, [frame(0.5, time: 1), frame(0.55, time: 1.01)], offset: start)
        XCTAssertGreaterThan(workspace.scrollingOffset, start)
        feed(controller, workspace, [frame(0.56, time: 1.02, fingers: 4)])
        XCTAssertEqual(workspace.scrollingOffset, start, accuracy: 0.01)
        XCTAssertFalse(controller.isMotionActive)
        XCTAssertTrue(focus.windowOrNil === windows[0])
    }

    func testReleaseRevealsNearestColumnAndPartialLiftCannotRestart() throws {
        let (workspace, windows) = fixture()
        let controller = WorkspaceScrollingGestureController(dependencies: .init(eligible: { true }, reduceMotion: { true }))
        defer { controller.reset() }
        feed(controller, workspace, [frame(0.5, time: 1), frame(0.37, time: 1.01)])
        let metrics = workspace.scrollingMetrics
        let center = workspace.scrollingOffset + metrics.areaWidth / 2
        let chosen = try XCTUnwrap(metrics.columns.min { abs($0.start + $0.width / 2 - center) < abs($1.start + $1.width / 2 - center) })
        let expected = metrics.revealedOffset(for: chosen, current: workspace.scrollingOffset)
        feed(controller, workspace, [frame(0.37, time: 1.02, fingers: 2)])
        XCTAssertEqual(workspace.scrollingOffset, expected, accuracy: 0.01)
        XCTAssertTrue(focus.windowOrNil === chosen.node.mostRecentWindowRecursive)
        XCTAssertFalse(controller.isMotionActive)
        let focused = focus.windowOrNil
        feed(controller, workspace, [frame(0.1, time: 1.03)])
        XCTAssertEqual(workspace.scrollingOffset, expected, accuracy: 0.01)
        XCTAssertTrue(focus.windowOrNil === focused)
        XCTAssertEqual(windows.count, 4)
    }

    func testExplicitFocusInterruptAndOwnerEpochRejectStaleSequence() {
        let (workspace, _) = fixture()
        let controller = WorkspaceScrollingGestureController(dependencies: .init(eligible: { true }, reduceMotion: { true }))
        defer { controller.reset() }
        let epoch = workspace.scrollingSessionEpoch
        feed(controller, workspace, [frame(0.5, time: 1), frame(0.4, time: 1.01)])
        controller.interruptForExplicitFocus()
        workspace.scrollingOffset = 123
        feed(controller, workspace, [frame(0.2, time: 1.02)], offset: 0)
        XCTAssertEqual(workspace.scrollingOffset, 123)
        feed(controller, workspace, [frame(0.2, time: 1.03, fingers: 0)])
        workspace.transitionArrangement(to: .dwindle)
        workspace.transitionArrangement(to: .scrolling)
        feed(controller, workspace, [frame(0.5, time: 2), frame(0.3, time: 2.01)], epoch: epoch, offset: 0)
        XCTAssertEqual(workspace.scrollingOffset, 123)
        XCTAssertFalse(controller.isMotionActive)
    }

    func testCancelledSettlementCannotOverrideNewFocusWhenItsClockReturnsLate() async throws {
        let (workspace, windows) = fixture()
        config.animations.enabled = true
        config.workspaceSwipe.animationDurationMs = 300
        let reachedFrame = expectation(description: "Settling frame")
        var continuation: CheckedContinuation<Void, Never>?
        var time: TimeInterval = 0
        let controller = WorkspaceScrollingGestureController(dependencies: .init(eligible: { true }, reduceMotion: { false },
            now: { time }, nextFrame: {
                await withCheckedContinuation { value in continuation = value; reachedFrame.fulfill() }
            }))
        defer { controller.reset(); continuation?.resume() }
        feed(controller, workspace, [frame(0.5, time: 1), frame(0.48, time: 1.01), frame(0.48, time: 1.02, fingers: 0)])
        await fulfillment(of: [reachedFrame], timeout: 2)
        let completion = try XCTUnwrap(controller.settlementCompletion)
        controller.interruptForExplicitFocus()
        _ = windows[3].focusWindow()
        workspace.scrollingOffset = 123
        time = 100
        continuation?.resume()
        continuation = nil
        await completion.value
        XCTAssertTrue(focus.windowOrNil === windows[3])
        XCTAssertEqual(workspace.scrollingOffset, 123)
        XCTAssertFalse(controller.isMotionActive)
        XCTAssertFalse(workspace.scrollingGestureMotionActive)
        XCTAssertNil(controller.settlementCompletion)
    }

    func testSharedSpringSamplesConvergeWithoutNativeLayer() {
        let animation = WorkspaceGestureAnimation.settlingAnimation(keyPath: "position.x", from: 10, to: 900, speed: 0, duration: 0.3)
        let spring = WorkspaceGestureScalarSpring(from: 10, to: 900, animation: animation)
        XCTAssertEqual(spring.value(at: 0), 10, accuracy: 0.001)
        XCTAssertGreaterThan(spring.value(at: 0.1), 10)
        XCTAssertLessThan(spring.value(at: 0.1), 900)
        XCTAssertEqual(spring.value(at: 10), 900, accuracy: 0.001)
    }
}
