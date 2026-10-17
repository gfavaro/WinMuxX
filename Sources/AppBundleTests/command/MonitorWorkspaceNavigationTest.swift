@testable import AppBundle
import Common
import XCTest

@MainActor
final class MonitorWorkspaceNavigationTest: XCTestCase {
    private var fixture: WorkspaceNavigationFixture!
    private var displays: [TestMonitor] { fixture.displays }
    private var spaces: [Workspace] { fixture.spaces }

    override func setUp() async throws {
        fixture = WorkspaceNavigationFixture()
    }

    override func tearDown() async throws {
        fixture.cleanUp()
        fixture = nil
    }

    private func run(_ command: String, stdin: String = "") async throws {
        let result = try await parseCommand(command).cmdOrDie.run(.defaultEnv, CmdStdin(stdin))
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined(separator: "\n"))
        checkWorkspaceHierarchyInvariants(requireActiveMonitorViewports: true)
    }

    func testSwipePreviewTargetSelectionDoesNotChangeAnyViewport() {
        spaces[2].seedMonitorIfNeeded(displays[1])
        spaces[3].seedMonitorIfNeeded(displays[2])
        let before = displays.map { $0.activeWorkspace.id }
        XCTAssertEqual(workspaceSwipeTarget(on: displays[1], isNext: true), spaces[2])
        XCTAssertNil(workspaceSwipeTarget(on: displays[0], isNext: true))
        XCTAssertEqual(displays.map { $0.activeWorkspace.id }, before)
        XCTAssertEqual(focus.workspace, spaces[0])
    }

    func testExplicitlyMovedWorkspaceBecomesSwipeReachableOnItsNewDisplay() {
        spaces[2].seedMonitorIfNeeded(displays[0])
        spaces[3].seedMonitorIfNeeded(displays[0])
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(spaces[4], targetMonitor: displays[0]))
        let otherDisplays = displays.dropFirst().map { $0.activeWorkspace.id }
        XCTAssertTrue(activateWorkspaceForUser(spaces[0], on: displays[0]))
        XCTAssertTrue(navigateWorkspaceBySwipe(on: displays[0], isNext: true))
        XCTAssertEqual(displays[0].activeWorkspace, spaces[2])
        XCTAssertTrue(navigateWorkspaceBySwipe(on: displays[0], isNext: true))
        XCTAssertEqual(displays[0].activeWorkspace, spaces[3])
        XCTAssertTrue(navigateWorkspaceBySwipe(on: displays[0], isNext: true))
        XCTAssertEqual(displays[0].activeWorkspace, spaces[4])
        XCTAssertEqual(displays.dropFirst().map { $0.activeWorkspace.id }, otherDisplays)
        XCTAssertEqual(spaces[4].workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
    }

    func testExplicitWorkspaceMoveCannotBeUndoneByOldRecoverySnapshot() async throws {
        resetClosedWindowsCache()
        defer { resetClosedWindowsCache() }
        let moved = spaces[4]
        let window = try XCTUnwrap(moved.allLeafWindowsRecursive.first)
        replaceClosedWindowsCache(snapshotCurrentFrozenWorld())
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(moved, targetMonitor: displays[0]))
        XCTAssertTrue(activateWorkspaceForUser(spaces[0], on: displays[0]))
        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        XCTAssertFalse(restored)
        XCTAssertEqual(moved.workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
        spaces[2].seedMonitorIfNeeded(displays[1])
        spaces[3].seedMonitorIfNeeded(displays[1])
        XCTAssertEqual(workspaceSwipeTarget(on: displays[0], isNext: true), moved)
    }

    func testReplacingSecondaryWorkspaceReturnsPreviousOwnerToMainForSwipes() {
        XCTAssertTrue(spaces[0].focusWorkspace())
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(spaces[2], targetMonitor: displays[1]))
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[2])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
        XCTAssertFalse(spaces[1].isVisible)
        XCTAssertEqual(spaces[1].workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
        XCTAssertEqual(workspaceSwipeTarget(on: displays[0], isNext: true), spaces[1])
        XCTAssertTrue(navigateWorkspaceBySwipe(on: displays[0], isNext: true))
        XCTAssertEqual(displays[0].activeWorkspace, spaces[1])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[2])
    }

    func testReplacingThirdDisplayAlsoReturnsItsHiddenWorkspacesToMain() {
        spaces[3].seedMonitorIfNeeded(displays[2])
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(spaces[2], targetMonitor: displays[2]))
        for workspace in [spaces[3], spaces[4]] {
            XCTAssertEqual(workspace.workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
            XCTAssertFalse(workspace.isVisible)
        }
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[2])
    }

    func testSwipeStaysWithinActiveProject() {
        let project = WorkspaceProjectId("swipe-other")
        spaces[2].assignProject(project)
        spaces[3].seedMonitorIfNeeded(displays[0])
        XCTAssertTrue(navigateWorkspaceBySwipe(on: displays[0], isNext: true))
        XCTAssertEqual(displays[0].activeWorkspace, spaces[3])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
    }

    func testSwipeNavigatesOnlyExistingLocalWorkspacesAndStopsAtEnds() {
        spaces[2].seedMonitorIfNeeded(displays[1])
        spaces[3].seedMonitorIfNeeded(displays[2])
        let ids = Set(Workspace.all.map(\.id))
        XCTAssertTrue(navigateWorkspaceBySwipe(on: displays[1], isNext: true))
        XCTAssertEqual(displays[1].activeWorkspace, spaces[2])
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
        XCTAssertFalse(navigateWorkspaceBySwipe(on: displays[1], isNext: true))
        XCTAssertTrue(navigateWorkspaceBySwipe(on: displays[1], isNext: false))
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertFalse(navigateWorkspaceBySwipe(on: displays[1], isNext: false))
        XCTAssertFalse(navigateWorkspaceBySwipe(on: displays[0], isNext: true))
        XCTAssertFalse(navigateWorkspaceBySwipe(on: displays[0], isNext: false))
        XCTAssertTrue(navigateWorkspaceBySwipe(on: displays[2], isNext: false))
        XCTAssertEqual(displays[2].activeWorkspace, spaces[3])
        XCTAssertFalse(navigateWorkspaceBySwipe(on: displays[2], isNext: false))
        XCTAssertEqual(Set(Workspace.all.map(\.id)), ids)
        XCTAssertEqual(spaces[2].workspaceMonitor.rect.topLeftCorner, displays[1].rect.topLeftCorner)
        XCTAssertEqual(spaces[4].workspaceMonitor.rect.topLeftCorner, displays[2].rect.topLeftCorner)
    }

    func testLateTreeRestorationPreservesStartupDisplayChoice() async throws {
        let workspace = spaces[2]
        workspace.seedMonitorIfNeeded(displays[1])
        let world = snapshotCurrentFrozenWorld()
        config.startWorkspacesOnMainMonitor = true
        applyStartupWorkspacePlacement()
        let window = try XCTUnwrap(workspace.allLeafWindowsRecursive.first)
        let restored = try await restoreFrozenWorldIfNeeded(world, newlyDetectedWindow: window,
            matchedWindows: [window.windowId: window], restoreVisibleWorkspaces: false)
        XCTAssertTrue(restored)
        XCTAssertEqual(workspace.workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
    }

    func testStartupPlacementIsOptionalAndExplicitMovesStillWork() async throws {
        config.startWorkspacesOnMainMonitor = false
        applyStartupWorkspacePlacement()
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])

        config.startWorkspacesOnMainMonitor = true
        config.workspaceToMonitorForceAssignment = ["5": [.sequenceNumber(3)]]
        applyStartupWorkspacePlacement()
        for workspace in spaces.prefix(4) {
            XCTAssertEqual(workspace.workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
        }
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
        XCTAssertTrue(displays[1].activeWorkspace.isEffectivelyEmpty)
        XCTAssertFalse(spaces.contains(displays[1].activeWorkspace))

        try await run("move-workspace-to-monitor 2 --workspace 2")
        try await run("workspace 1")
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
    }

    func testAutomaticSelectionCannotTakeHiddenWorkspaceFromAnotherDisplay() {
        let hidden = spaces[2]
        hidden.seedMonitorIfNeeded(displays[0])
        XCTAssertFalse(workspaceIsAvailableForMonitor(hidden, monitor: displays[1]))
        XCTAssertTrue(workspaceIsAvailableForMonitor(hidden, monitor: displays[0]))
        XCTAssertNotEqual(availablePreferredWorkspace(projectId: hidden.projectId, monitor: displays[1]), hidden)

        // Fallback creation must leave even an empty owned workspace on its display.
        let empty = Workspace.get(byName: "owned-empty")
        empty.seedMonitorIfNeeded(displays[0])
        let fallback = getOrCreateMonitorViewportFallbackWorkspace(for: displays[1])
        XCTAssertNotEqual(fallback, empty)
        XCTAssertEqual(empty.workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
    }

    func testDirectSelectionOnlyFocusesDestinationAndPreservesHistory() async throws {
        for display in displays {
            runtime.workspaces.monitorViewportsById[MonitorViewportId(display)]?.previousWorkspaceId = spaces[3].id
        }
        let before = runtime.workspaces.monitorViewportsById
        try await run("workspace 2")
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
        XCTAssertEqual(focus.windowOrNil?.windowId, 902)
        XCTAssertEqual(focus.workspace.workspaceMonitor.rect.topLeftCorner, displays[1].rect.topLeftCorner)
        for (id, viewport) in before {
            XCTAssertEqual(runtime.workspaces.monitorViewportsById[id]?.previousWorkspaceId, viewport.previousWorkspaceId)
            XCTAssertEqual(runtime.workspaces.monitorViewportsById[id]?.activeWorkspaceId, viewport.activeWorkspaceId)
        }
    }

    func testRelativeNavigationSkipsOtherDisplaysAndPreservesStdinOrder() async throws {
        try await run("workspace next")
        XCTAssertEqual(focus.workspace, spaces[2])
        try await run("workspace --stdin next", stdin: "3\n5\n2\n4")
        XCTAssertEqual(focus.workspace, spaces[3])
        try await run("workspace next --wrap-around")
        XCTAssertEqual(focus.workspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
    }

    func testHistoryIsIndependentAndMonitorFocusDoesNotChangeIt() async throws {
        try await run("workspace --name 3")
        try await run("workspace --monitor 2 --name 4")
        XCTAssertEqual(focus.workspace, spaces[3])
        try await run("workspace-back-and-forth")
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(displays[0].activeWorkspace, spaces[2])
        XCTAssertTrue(spaces[2].focusWorkspace())
        try await run("workspace-back-and-forth")
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
    }

    func testExplicitMonitorAutoBackAndForthUsesItsOwnHistory() async throws {
        try await run("workspace --monitor 2 --name 4")
        XCTAssertTrue(spaces[0].focusWorkspace())
        try await run("workspace --monitor 2 --name 4 --auto-back-and-forth")
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(focus.workspace, spaces[1])
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
    }

    func testForcedSourceAssignmentDoesNotBlockCrossMonitorFocus() async throws {
        config.workspaceToMonitorForceAssignment = ["1": [.main]]
        for display in displays {
            runtime.workspaces.monitorViewportsById[MonitorViewportId(display)]?.previousWorkspaceId = spaces[3].id
        }
        let before = runtime.workspaces.monitorViewportsById
        let result = try await parseCommand("workspace --name 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(focus.workspace, spaces[1])
        for (id, viewport) in before {
            XCTAssertEqual(runtime.workspaces.monitorViewportsById[id]?.previousWorkspaceId, viewport.previousWorkspaceId)
        }
    }

    func testRelativeNavigationSkipsForcedAssignments() async throws {
        config.workspaceToMonitorForceAssignment = ["3": [.sequenceNumber(2)]]
        try await run("workspace next")
        XCTAssertEqual(focus.workspace, spaces[3])
    }

    func testSidebarFocusesWorkspaceOnItsExistingDisplay() {
        XCTAssertTrue(focusWorkspaceFromSidebar(spaces[0], targetMonitorScopeId: workspaceSidebarMonitorScopeId(for: displays[1])))
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(focus.workspace.workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
    }

    func testForcedDestinationAssignmentAllowsFocusOnItsExistingMonitor() async throws {
        config.workspaceToMonitorForceAssignment = ["2": [.sequenceNumber(2)]]
        let result = try await parseCommand("workspace --name 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(focus.workspace, spaces[1])
    }

    func testForcedHiddenWorkspaceActivatesOnItsAssignedMonitor() async throws {
        config.workspaceToMonitorForceAssignment = ["3": [.sequenceNumber(2)]]
        let result = try await parseCommand("workspace --name 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[2])
        XCTAssertEqual(focus.workspace, spaces[2])
    }

    func testAlreadyFocusedVisibleWorkspaceIsNoopEvenWhenAnotherMonitorIsRequested() async throws {
        let result = try await parseCommand("workspace --monitor 2 --name 1 --fail-if-noop").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(focus.workspace, spaces[0])
    }

    func testAdvancingPastAvailableWorkspacesCreatesEmptyWorkspaceOnFocusedDisplay() async throws {
        spaces.forEach { $0.markAsAutomaticallyNamed() }
        try await run("workspace --name 4")
        try await run("workspace next")
        XCTAssertNil(focus.windowOrNil)
        XCTAssertTrue(focus.workspace.isEffectivelyEmpty)
        XCTAssertEqual(focus.workspace.workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
    }

    func testMissingHistoryDoesNotCreateAWorkspaceOrChangeFocus() async throws {
        runtime.workspaces.monitorViewportsById[MonitorViewportId(displays[0])]?.previousWorkspaceId = WorkspaceId("removed")
        let workspaceIds = Set(Workspace.all.map(\.id))
        let result = try await parseCommand("workspace-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(Set(Workspace.all.map(\.id)).isSubset(of: workspaceIds))
        XCTAssertEqual(focus.workspace, spaces[0])
    }

    func testDisconnectAndReconnectPreservesSurvivingDisplayHistory() async throws {
        try await run("workspace --name 3")
        setMonitorsForTests([displays[0]])
        rearrangeWorkspacesOnMonitors()
        checkWorkspaceHierarchyInvariants(requireActiveMonitorViewports: true)
        setMonitorsForTests(displays)
        rearrangeWorkspacesOnMonitors()
        checkWorkspaceHierarchyInvariants(requireActiveMonitorViewports: true)
        XCTAssertEqual(runtime.workspaces.monitorViewportsById[MonitorViewportId(displays[0])]?.previousWorkspaceId, spaces[0].id)
        try await run("workspace-back-and-forth")
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
    }
    func testSidebarOverrideBringsWorkspaceToDestinationWithoutSwapping() {
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(spaces[0], targetMonitor: displays[1]))
        XCTAssertNotEqual(displays[0].activeWorkspace, spaces[1])
        XCTAssertTrue(displays[0].activeWorkspace.isEffectivelyEmpty)
        XCTAssertEqual(spaces[1].workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
        XCTAssertFalse(spaces[1].isVisible)
        XCTAssertEqual(displays[1].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
        XCTAssertTrue(focusWorkspaceFromSidebar(spaces[0], targetMonitorScopeId: workspaceSidebarMonitorScopeId(for: displays[1])))
        XCTAssertEqual(focus.workspace, spaces[0])
    }

    func testOverrideUsesThirdDisplayAndRejectsInvalidAssignmentWithoutChanges() {
        config.workspaceToMonitorForceAssignment = ["1": [.sequenceNumber(1)]]
        XCTAssertFalse(activateWorkspaceOnMonitorPreservingSourceViewport(spaces[0], targetMonitor: displays[2]))
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
        config.workspaceToMonitorForceAssignment = [:]
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(spaces[0], targetMonitor: displays[2]))
        XCTAssertEqual(displays[2].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertFalse(spaces[4].isVisible)
        XCTAssertEqual(spaces[4].workspaceMonitor.rect.topLeftCorner, displays[0].rect.topLeftCorner)
    }

}
