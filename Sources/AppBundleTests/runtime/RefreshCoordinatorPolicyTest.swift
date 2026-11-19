@testable import AppBundle
import AppKit
import Common
import XCTest

/// The scheduling rules on their own, without running a refresh: when an event is dropped,
/// joins the owed follow-up or starts a session, and how a light session takes over.
@MainActor
final class RefreshCoordinatorPolicyTest: XCTestCase {
    private let moved = RefreshSessionEvent.ax(kAXMovedNotification as String)
    private let created = RefreshSessionEvent.ax(kAXWindowCreatedNotification as String)

    private func running(_ coordinator: RefreshCoordinator, _ event: RefreshSessionEvent) {
        coordinator.active = ActiveRefresh(task: Task {}, event: event)
    }

    private func started(_ admission: RefreshCoordinator.Admission) -> (event: String, generation: UInt64)? {
        guard case .start(let event, _, let generation) = admission else { return nil }
        return (event.description, generation)
    }

    func testIdleStartsASessionWithANewGeneration() {
        let coordinator = RefreshCoordinator()
        let first = started(coordinator.admit(created, optimisticallyPreLayoutWorkspaces: false))
        XCTAssertEqual(first?.event, created.description)
        XCTAssertEqual(first?.generation, 1)
        XCTAssertNil(coordinator.pendingRefreshRequest)
    }

    func testEventsDuringASessionJoinOneFollowUpKeepingTheMostDemanding() {
        let coordinator = RefreshCoordinator()
        running(coordinator, .hotkeyBinding)
        guard case .coalesced = coordinator.admit(.onModeChanged, optimisticallyPreLayoutWorkspaces: false) else { return XCTFail() }
        guard case .coalesced = coordinator.admit(created, optimisticallyPreLayoutWorkspaces: true) else { return XCTFail() }
        XCTAssertEqual(coordinator.pendingRefreshRequest?.event.description, created.description)
        XCTAssertEqual(coordinator.pendingRefreshRequest?.optimisticallyPreLayoutWorkspaces, true)
    }

    func testAMoveIsDroppedWhileAGeometryOrMouseResetSessionCoversIt() {
        let coordinator = RefreshCoordinator()
        running(coordinator, moved)
        guard case .dropped = coordinator.admit(moved, optimisticallyPreLayoutWorkspaces: false) else { return XCTFail() }
        running(coordinator, .resetManipulatedWithMouse)
        guard case .dropped = coordinator.admit(moved, optimisticallyPreLayoutWorkspaces: false) else { return XCTFail() }
        running(coordinator, .hotkeyBinding)
        guard case .coalesced = coordinator.admit(moved, optimisticallyPreLayoutWorkspaces: false) else { return XCTFail() }
    }

    func testParkingRepairNeverReplacesOwedWork() {
        XCTAssertEqual(RefreshCoordinator.merge(.onTabSwitched, .onWindowParkingDrift).description, RefreshSessionEvent.onTabSwitched.description)
        XCTAssertEqual(RefreshCoordinator.merge(.onWindowParkingDrift, .onModeChanged).description, RefreshSessionEvent.onModeChanged.description)
    }

    func testAFinishedSessionHandsBackItsFollowUpOnlyIfStillTheOwner() {
        let coordinator = RefreshCoordinator()
        guard let session = started(coordinator.admit(.hotkeyBinding, optimisticallyPreLayoutWorkspaces: false)) else { return XCTFail() }
        running(coordinator, .hotkeyBinding)
        _ = coordinator.admit(created, optimisticallyPreLayoutWorkspaces: false)
        XCTAssertEqual(coordinator.finishScheduled(generation: session.generation)?.event.description, created.description)
        XCTAssertNil(coordinator.active)
        XCTAssertNil(coordinator.pendingRefreshRequest)

        guard let next = started(coordinator.admit(.hotkeyBinding, optimisticallyPreLayoutWorkspaces: false)) else { return XCTFail() }
        running(coordinator, .hotkeyBinding)
        _ = coordinator.admit(created, optimisticallyPreLayoutWorkspaces: false)
        coordinator.stopActive()
        XCTAssertNil(coordinator.finishScheduled(generation: next.generation), "a superseded session leaves the follow-up to its successor")
        XCTAssertNotNil(coordinator.pendingRefreshRequest)
    }

    func testALightSessionKeepsTheInterruptedWorkOwed() {
        let coordinator = RefreshCoordinator()
        guard let session = started(coordinator.admit(created, optimisticallyPreLayoutWorkspaces: false)) else { return XCTFail() }
        running(coordinator, created)
        let light = coordinator.beginLight()
        XCTAssertGreaterThan(light, session.generation)
        XCTAssertNil(coordinator.active)
        XCTAssertNil(coordinator.finishScheduled(generation: session.generation), "the interrupted session no longer owns the follow-up")
        XCTAssertEqual(coordinator.owedAfterLight(generation: light)?.event.description, created.description)
    }

    func testALightSessionLeavesOwedWorkToANewerSession() {
        let coordinator = RefreshCoordinator()
        let light = coordinator.beginLight()
        _ = coordinator.admit(created, optimisticallyPreLayoutWorkspaces: false)
        running(coordinator, created)
        XCTAssertNil(coordinator.owedAfterLight(generation: light))
    }
}
