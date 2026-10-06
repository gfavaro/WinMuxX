@testable import AppBundle
import Common
import XCTest

@MainActor
final class MonitorWorkspaceNavigationTest: XCTestCase {
    private var displays: [TestMonitor] = []
    private var spaces: [Workspace] = []

    override func setUp() async throws {
        setUpWorkspacesForTests()
        displays = (0..<3).map { index in
            let rect = Rect(topLeftX: Double(index * 1920), topLeftY: 0, width: 1920, height: 1080)
            return TestMonitor(monitorAppKitNsScreenScreensId: index + 1, name: "Display\(index + 1)", rect: rect, visibleRect: rect, isMain: index == 0)
        }
        setMonitorsForTests(displays)
        spaces = (1...5).map { index in
            let workspace = Workspace.get(byName: String(index))
            TestWindow.new(id: UInt32(900 + index), parent: workspace.rootTilingContainer).markAsMostRecentChild()
            return workspace
        }
        XCTAssertTrue(displays[0].setActiveWorkspace(spaces[0]))
        XCTAssertTrue(displays[1].setActiveWorkspace(spaces[1]))
        XCTAssertTrue(displays[2].setActiveWorkspace(spaces[4]))
        XCTAssertTrue(spaces[0].focusWorkspace())
    }

    override func tearDown() async throws { setMonitorsForTests(nil) }

    private func run(_ command: String, stdin: String = "") async throws {
        let result = try await parseCommand(command).cmdOrDie.run(.defaultEnv, CmdStdin(stdin))
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined(separator: "\n"))
        checkWorkspaceHierarchyInvariants(requireActiveMonitorViewports: true)
    }

    func testDirectSelectionOnlyFocusesDestinationAndPreservesHistory() async throws {
        for display in displays {
            winMuxWorkspaceState.monitorViewportsById[MonitorViewportId(display)]?.previousWorkspaceId = spaces[3].id
        }
        let before = winMuxWorkspaceState.monitorViewportsById
        try await run("workspace 2")
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
        XCTAssertEqual(focus.windowOrNil?.windowId, 902)
        XCTAssertEqual(focus.workspace.workspaceMonitor.rect.topLeftCorner, displays[1].rect.topLeftCorner)
        for (id, viewport) in before {
            XCTAssertEqual(winMuxWorkspaceState.monitorViewportsById[id]?.previousWorkspaceId, viewport.previousWorkspaceId)
            XCTAssertEqual(winMuxWorkspaceState.monitorViewportsById[id]?.activeWorkspaceId, viewport.activeWorkspaceId)
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
            winMuxWorkspaceState.monitorViewportsById[MonitorViewportId(display)]?.previousWorkspaceId = spaces[3].id
        }
        let before = winMuxWorkspaceState.monitorViewportsById
        let result = try await parseCommand("workspace --name 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(focus.workspace, spaces[1])
        for (id, viewport) in before {
            XCTAssertEqual(winMuxWorkspaceState.monitorViewportsById[id]?.previousWorkspaceId, viewport.previousWorkspaceId)
        }
    }

    func testRelativeNavigationSkipsForcedAssignments() async throws {
        config.workspaceToMonitorForceAssignment = ["3": [.sequenceNumber(2)]]
        try await run("workspace next")
        XCTAssertEqual(focus.workspace, spaces[3])
    }

    func testSidebarRequiresOverrideForWorkspaceVisibleOnAnotherDisplay() {
        XCTAssertFalse(focusWorkspaceFromSidebar(spaces[0], targetMonitorScopeId: workspaceSidebarMonitorScopeId(for: displays[1])))
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

    func testForcedHiddenWorkspaceStillCannotActivateOnWrongMonitor() async throws {
        config.workspaceToMonitorForceAssignment = ["3": [.sequenceNumber(2)]]
        let result = try await parseCommand("workspace --name 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[1])
        XCTAssertEqual(focus.workspace, spaces[0])
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
        winMuxWorkspaceState.monitorViewportsById[MonitorViewportId(displays[0])]?.previousWorkspaceId = WorkspaceId("removed")
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
        XCTAssertEqual(winMuxWorkspaceState.monitorViewportsById[MonitorViewportId(displays[0])]?.previousWorkspaceId, spaces[0].id)
        try await run("workspace-back-and-forth")
        XCTAssertEqual(displays[0].activeWorkspace, spaces[0])
    }
    func testSidebarOverrideSwapsOnlyTheSourceAndDestinationDisplays() {
        XCTAssertTrue(overrideWorkspaceOnMonitorBySwappingActiveViewports(spaces[0], targetMonitor: displays[1]))
        XCTAssertEqual(displays[0].activeWorkspace, spaces[1])
        XCTAssertEqual(displays[1].activeWorkspace, spaces[0])
        XCTAssertEqual(displays[2].activeWorkspace, spaces[4])
        XCTAssertTrue(focusWorkspaceFromSidebar(spaces[0], targetMonitorScopeId: workspaceSidebarMonitorScopeId(for: displays[1])))
        XCTAssertEqual(focus.workspace, spaces[0])
    }

}
