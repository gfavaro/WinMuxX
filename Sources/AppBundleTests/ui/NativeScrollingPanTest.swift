@testable import AppBundle
import AppKit
import Common
@testable import NativeSpaces
import XCTest

@MainActor
final class NativeScrollingPanTest: WorkspaceTestCase {
    /// An observed native desktop showing on the test display.
    private func nativeDesktop() -> Workspace {
        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let monitor = TestMonitor(displayUUID: "display-a", monitorAppKitNsScreenScreensId: 1,
            name: "display-a", rect: rect, visibleRect: rect, isMain: true)
        setMonitorsForTests([monitor])
        var inventory = NativeWorkspaceInventory()
        _ = inventory.publish(NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a", activeSpaceID: "1",
            spaces: [NativeSpace(id: "1", uuid: "desktop-a", type: 0)])], windows: [], readMilliseconds: 0, capturedAt: .now),
            for: inventory.invalidate())
        runtime.workspaceBackend.nativeLayouts.reconcile(inventory, displays: [monitor])
        return runtime.workspaceBackend.nativeLayouts.retainedByUUID["desktop-a"]!
    }

    private func fixture() -> (Workspace, [TestWindow]) {
        let workspace = nativeDesktop()
        workspace.rootTilingContainer.layout = .tiles
        let windows = (0..<4).map { TestWindow.new(id: UInt32(97000 + $0), parent: workspace.rootTilingContainer) }
        windows.forEach { $0.scrollingColumnWidth = 0.7 }
        workspace.transitionArrangement(to: .scrolling)
        _ = windows[0].focusWindow()
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
        let workspace = nativeDesktop()
        TestWindow.new(id: 97100, parent: workspace.rootTilingContainer)
        XCTAssertFalse(NativeScrollingPan().handle(scroll(-120, at: workspace.workspaceMonitor.rect.center)))
    }

    func testADisplayShowingAFullscreenSpaceHasNoDesktopAndCreatesNone() {
        let desktop = nativeDesktop()
        var inventory = NativeWorkspaceInventory()
        _ = inventory.publish(NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a", activeSpaceID: "9",
            spaces: [NativeSpace(id: "1", uuid: "desktop-a", type: 0), NativeSpace(id: "9", uuid: "full", type: 4)])],
            windows: [], readMilliseconds: 0, capturedAt: .now), for: inventory.invalidate())
        runtime.workspaceBackend.nativeLayouts.reconcile(inventory, displays: [desktop.workspaceMonitor])
        let before = Workspace.all.count
        XCTAssertNil(nativeActiveDesktop(on: desktop.workspaceMonitor))
        XCTAssertFalse(NativeScrollingPan().handle(scroll(-120, at: desktop.workspaceMonitor.rect.center)))
        XCTAssertEqual(Workspace.all.count, before, "No virtual workspace is created for the display")
    }
}
