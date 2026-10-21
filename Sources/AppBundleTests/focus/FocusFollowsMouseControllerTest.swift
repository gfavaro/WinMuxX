@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class FocusFollowsMouseControllerTest: XCTestCase {
    func testPointerTargetRespectsMonitorFloatingWindowsAndOcclusion() {
        setUpWorkspacesForTests()
        defer { setMonitorsForTests(nil); setUpWorkspacesForTests() }
        let leftRect = Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 800)
        let rightRect = Rect(topLeftX: 1000, topLeftY: 0, width: 1000, height: 800)
        let left = TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "Left", rect: leftRect, visibleRect: leftRect, isMain: true)
        let right = TestMonitor(monitorAppKitNsScreenScreensId: 2, name: "Right", rect: rightRect, visibleRect: rightRect, isMain: false)
        setMonitorsForTests([left, right])
        let workspace = focus.workspace
        _ = left.setActiveWorkspace(workspace)
        let other = Workspace.get(byName: "right")
        _ = right.setActiveWorkspace(other)
        workspace.rootTilingContainer.layout = .tabGroup
        workspace.rootTilingContainer.lastAppliedLayoutPhysicalRect = leftRect
        let tiled = TestWindow.new(id: 400, parent: workspace.rootTilingContainer)
        tiled.lastAppliedLayoutPhysicalRect = leftRect
        let floating = TestWindow.new(id: 401, parent: workspace)
        floating.recordAuthoritativeActualRect(Rect(topLeftX: 100, topLeftY: 100, width: 300, height: 200))
        let rightWindow = TestWindow.new(id: 402, parent: other.rootTilingContainer)
        other.rootTilingContainer.lastAppliedLayoutPhysicalRect = rightRect
        rightWindow.lastAppliedLayoutPhysicalRect = rightRect
        XCTAssertNil(CGPoint(x: 1100, y: 100).findIn(tree: workspace.rootTilingContainer, virtual: false))
        XCTAssertTrue(pointerFocusCandidate(at: CGPoint(x: 150, y: 150)) === floating)
        XCTAssertTrue(pointerFocusCandidate(at: CGPoint(x: 1100, y: 100)) === rightWindow)
        XCTAssertTrue(pointerFocusTarget(at: CGPoint(x: 150, y: 150), frontmostWindowId: floating.windowId) === floating)
        XCTAssertNil(pointerFocusTarget(at: CGPoint(x: 150, y: 150), frontmostWindowId: 999))
        XCTAssertNil(pointerFocusTarget(at: CGPoint(x: 150, y: 150), frontmostWindowId: rightWindow.windowId))
    }

    func testRepeatedStationaryEventsPreserveTheDwellCandidate() {
        let controller = FocusFollowsMouseController()
        _ = controller.notePointer(windowId: 1, point: .zero, timestamp: 1)
        let original = controller.candidate
        for tick in 1...1_000 {
            _ = controller.notePointer(windowId: 1, point: .zero, timestamp: 1 + Double(tick) / 1_000)
            XCTAssertEqual(controller.candidate, original)
        }
        XCTAssertEqual(controller.isReady(dwell: 0.25, timestamp: 2), 1)
    }

    func testDisablingWinMuxClearsPendingPointerFocusBeforeReenable() async throws {
        setUpWorkspacesForTests()
        let previousEnabled = TrayMenuModel.shared.isEnabled
        defer {
            TrayMenuModel.shared.isEnabled = previousEnabled
            GlobalObserver.cancelFocusFollowsMouse()
        }
        TrayMenuModel.shared.isEnabled = true
        config.focusFollowsMouse = true
        _ = FocusFollowsMouseController.shared.notePointer(windowId: 1, point: .zero, timestamp: 1)

        let result = try await EnableCommand(args: EnableCmdArgs(rawArgs: ["off"], targetState: .off))
            .run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(TrayMenuModel.shared.isEnabled)
        XCTAssertNil(FocusFollowsMouseController.shared.candidate)
        TrayMenuModel.shared.isEnabled = true
        XCTAssertNil(FocusFollowsMouseController.shared.isReady(dwell: 0, timestamp: 2))
    }

    func testRequiresPointerToRemainOnTheSameWindowForDwell() {
        let controller = FocusFollowsMouseController()
        XCTAssertNil(controller.notePointer(windowId: 1, point: CGPoint(x: 10, y: 10), timestamp: 1))
        XCTAssertNil(controller.isReady(dwell: 0.5, timestamp: 1.4))
        XCTAssertNil(controller.notePointer(windowId: 1, point: CGPoint(x: 11, y: 10), timestamp: 1.5))
        XCTAssertNil(controller.isReady(dwell: 0.5, timestamp: 1.9))
        XCTAssertEqual(controller.isReady(dwell: 0.5, timestamp: 2.0), 1)
    }

    func testChangingWindowCancelsPreviousCandidate() {
        let controller = FocusFollowsMouseController()
        _ = controller.notePointer(windowId: 1, point: .zero, timestamp: 1)
        _ = controller.notePointer(windowId: 2, point: .zero, timestamp: 1.2)
        XCTAssertNil(controller.isReady(dwell: 0.5, timestamp: 1.6))
        XCTAssertEqual(controller.isReady(dwell: 0.5, timestamp: 1.7), 2)
    }

    func testExplicitCancellationClearsCandidate() {
        let controller = FocusFollowsMouseController()
        _ = controller.notePointer(windowId: 1, point: .zero, timestamp: 1)
        controller.cancel()
        XCTAssertNil(controller.isReady(dwell: 0, timestamp: 2))
    }
}
