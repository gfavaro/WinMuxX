@testable import AppBundle
import XCTest

@MainActor
final class ScrollingReceiverLifecycleTest: WorkspaceTestCase {
    func testReceiverLifecycleAcrossArrangementAndDisplayChanges() throws {
        let workspace = focus.workspace
        workspace.rootTilingContainer.layout = .tiles
        let windows = (0..<4).map { TestWindow.new(id: UInt32(88000 + $0), parent: workspace.rootTilingContainer) }
        _ = windows[0].focusWindow()
        workspace.transitionArrangement(to: .scrolling)
        let receiver = DockScrollingSwipeReceiver(targetOverride: { workspace })
        let identity = workspace.id
        let originalFocus = focus.windowOrNil
        XCTAssertEqual(receiver.dockSwipeBegan(positive: true, progress: 0, timestamp: 0), .started)
        XCTAssertNotNil(workspace.scrollingState.gestureSessionID)
        receiver.dockSwipeChanged(0.2, timestamp: 1)
        XCTAssertGreaterThan(workspace.scrollingState.offset, 0)
        let offset = workspace.scrollingState.offset
        workspace.transitionArrangement(to: .dwindle)
        XCTAssertNil(workspace.scrollingState.gestureSessionID)
        XCTAssertFalse(workspace.scrollingState.gestureMotionActive)
        receiver.dockSwipeChanged(0.4, timestamp: 2)
        XCTAssertEqual(workspace.scrollingState.offset, offset)
        XCTAssertTrue(focus.windowOrNil === originalFocus)
        workspace.transitionArrangement(to: .scrolling)
        receiver.dockSwipeChanged(0.6, timestamp: 3)
        // Current receiver accepts this callback after the arrangement returns.
        XCTAssertGreaterThan(workspace.scrollingState.offset, offset)
        XCTAssertEqual(workspace.id, identity)
        XCTAssertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.elementsEqual(windows, by: ===))
        XCTAssertTrue(focus.windowOrNil === originalFocus)
        receiver.dockSwipeEnded(commit: false, progress: 0.6, velocity: 0, timestamp: 4)
        let endedOffset = workspace.scrollingState.offset
        receiver.dockSwipeChanged(0.9, timestamp: 5)
        XCTAssertEqual(workspace.scrollingState.offset, endedOffset)
        XCTAssertNil(workspace.scrollingState.gestureSessionID)
        XCTAssertFalse(workspace.scrollingState.gestureMotionActive)
        XCTAssertTrue(focus.windowOrNil === originalFocus)
    }

    func testCommittedEndReleasesReceiverAndFocusesColumn() {
        let workspace = focus.workspace
        workspace.rootTilingContainer.layout = .tiles
        let windows = (0..<4).map { TestWindow.new(id: UInt32(88200 + $0), parent: workspace.rootTilingContainer) }
        _ = windows[0].focusWindow()
        workspace.transitionArrangement(to: .scrolling)
        let receiver = DockScrollingSwipeReceiver(targetOverride: { workspace })
        XCTAssertEqual(receiver.dockSwipeBegan(positive: true, progress: 0, timestamp: 0), .started)
        receiver.dockSwipeChanged(0.6, timestamp: 1)
        receiver.dockSwipeEnded(commit: true, progress: 0.6, velocity: 0, timestamp: 2)
        let settledFocus = focus.windowOrNil
        let offset = workspace.scrollingState.offset
        XCTAssertNotNil(settledFocus)
        XCTAssertNil(workspace.scrollingState.gestureSessionID)
        XCTAssertFalse(workspace.scrollingState.gestureMotionActive)
        receiver.dockSwipeChanged(0.9, timestamp: 3)
        XCTAssertEqual(workspace.scrollingState.offset, offset)
        XCTAssertTrue(focus.windowOrNil === settledFocus)
        XCTAssertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.elementsEqual(windows, by: ===))
    }

    func testReceiverAcceptsCallbackAfterDisplayOwnershipChanges() {
        let fixture = WorkspaceNavigationFixture()
        defer { fixture.cleanUp() }
        let workspace = fixture.spaces[0]
        workspace.rootTilingContainer.children.forEach { $0.unbindFromParent() }
        workspace.rootTilingContainer.layout = .tiles
        let windows = (0..<4).map { TestWindow.new(id: UInt32(88100 + $0), parent: workspace.rootTilingContainer) }
        _ = windows[0].focusWindow()
        workspace.transitionArrangement(to: .scrolling)
        let receiver = DockScrollingSwipeReceiver(targetOverride: { workspace })
        XCTAssertEqual(receiver.dockSwipeBegan(positive: true, progress: 0, timestamp: 0), .started)
        let session = workspace.scrollingState.gestureSessionID
        let epoch = workspace.scrollingState.sessionEpoch
        let originalFocus = focus.windowOrNil
        let identity = workspace.id
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(workspace, targetMonitor: fixture.displays[1]))
        XCTAssertEqual(workspace.visibleMonitor?.rect.topLeftCorner, fixture.displays[1].rect.topLeftCorner)
        XCTAssertNotEqual(workspace.scrollingState.sessionEpoch, epoch)
        receiver.dockSwipeChanged(0.3, timestamp: 1)
        XCTAssertGreaterThan(workspace.scrollingState.offset, 0)
        XCTAssertEqual(workspace.scrollingState.gestureSessionID, session)
        XCTAssertEqual(workspace.id, identity)
        XCTAssertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.elementsEqual(windows, by: ===))
        XCTAssertTrue(focus.windowOrNil === originalFocus)
        receiver.dockSwipeEnded(commit: false, progress: 0.3, velocity: 0, timestamp: 2)
        XCTAssertNil(workspace.scrollingState.gestureSessionID)
    }
}
