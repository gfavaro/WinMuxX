@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class FocusFollowsMouseControllerTest: XCTestCase {
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
