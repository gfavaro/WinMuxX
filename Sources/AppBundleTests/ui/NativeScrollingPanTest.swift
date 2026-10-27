@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class NativeScrollingPanTest: WorkspaceTestCase {
    private func fixture() -> (Workspace, [TestWindow]) {
        let workspace = focus.workspace
        workspace.rootTilingContainer.layout = .tiles
        let windows = (0..<4).map { TestWindow.new(id: UInt32(97000 + $0), parent: workspace.rootTilingContainer) }
        windows.forEach { $0.scrollingColumnWidth = 0.7 }
        workspace.transitionArrangement(to: .scrolling)
        _ = windows[0].focusWindow()
        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        return (workspace, windows)
    }

    private func scroll(_ dx: CGFloat, dy: CGFloat = 0, option: Bool = true, continuous: Bool = true,
                        phase: Int64 = 2, momentum: Int64 = 0, at point: CGPoint) -> NativeScrollingPan.Scroll {
        .init(deltaX: dx, deltaY: dy, isContinuous: continuous, optionOnly: option, phase: phase,
              momentumPhase: momentum, point: point)
    }

    func testOnlyOptionHorizontalTrackpadScrollOverAScrollingDesktopPans() {
        let (workspace, _) = fixture()
        let pan = NativeScrollingPan()
        let point = workspace.workspaceMonitor.rect.center
        XCTAssertFalse(pan.handle(scroll(-80, option: false, at: point)), "Plain scroll stays with the app")
        XCTAssertFalse(pan.handle(scroll(-5, dy: -40, at: point)), "Vertical scroll stays with the app")
        XCTAssertFalse(pan.handle(scroll(-80, continuous: false, at: point)), "Mouse wheels stay with the app")
        let before = workspace.scrollingOffset
        XCTAssertTrue(pan.handle(scroll(-120, phase: 1, at: point)))
        XCTAssertGreaterThan(workspace.scrollingOffset, before, "Fingers moving left reveal columns to the right")
        XCTAssertTrue(workspace.scrollingGestureMotionActive)
        let panned = workspace.scrollingOffset
        XCTAssertTrue(pan.handle(scroll(0, phase: 4, at: point)))
        XCTAssertTrue(workspace.scrollingGestureMotionActive, "Lifting the fingers waits for macOS's momentum")
        XCTAssertTrue(pan.handle(scroll(-60, option: false, phase: 0, momentum: 2, at: point)), "Momentum belongs to the pan")
        XCTAssertGreaterThan(workspace.scrollingOffset, panned, "Momentum keeps moving the desktop")
        XCTAssertTrue(pan.handle(scroll(0, option: false, phase: 0, momentum: 3, at: point)))
        XCTAssertFalse(workspace.scrollingGestureMotionActive)
        XCTAssertEqual(pan.lastDecision, "panning")
        XCTAssertFalse(pan.isPanning)
        XCTAssertTrue(nativePanIgnoresNotification(kAXWindowMovedNotification as String), "Its own moves keep the permits")
        XCTAssertFalse(nativePanIgnoresNotification(kAXWindowMiniaturizedNotification as String), "Ownership changes still revoke")
        let metrics = workspace.scrollingMetrics
        XCTAssertTrue(metrics.columns.contains { metrics.revealedOffset(for: $0, current: workspace.scrollingOffset) == workspace.scrollingOffset },
            "The pan ends with a whole column revealed")
    }

    func testNonScrollingDesktopsKeepTheirScrollEvents() {
        let workspace = focus.workspace
        TestWindow.new(id: 97100, parent: workspace.rootTilingContainer)
        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        XCTAssertFalse(NativeScrollingPan().handle(scroll(-120, at: workspace.workspaceMonitor.rect.center)))
    }
}
