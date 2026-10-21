@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WorkspaceRetentionTest: WorkspaceTestCase {
    func testPersistentSlotsAreStableAcrossReconciliation() {
        let focused = focus.workspace
        config.persistentWorkspaces = [focused.name, "2", "3", "4"]
        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(Workspace.all.count, 4)
        XCTAssertTrue(focus.workspace === focused)
        XCTAssertTrue(Workspace.all.allSatisfy { isUserFacingWorkspace($0) })
        let identities = Set(Workspace.all.map(\.id))
        for _ in 0..<3 { Workspace.reconcileWorkspaceState() }
        XCTAssertEqual(Set(Workspace.all.map(\.id)), identities)
    }

    func testUnconfiguredHiddenEmptyWorkspacesAreCollected() {
        let occupied = focus.workspace
        _ = TestWindow.new(id: 8101, parent: occupied.rootTilingContainer)
        _ = Workspace.get(byName: "spare-one")
        _ = Workspace.get(byName: "spare-two")
        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(Workspace.all, [occupied])
    }

    func testRemovingPersistenceKeepsOccupiedAndRequiredProjectSlots() {
        let occupied = focus.workspace
        _ = TestWindow.new(id: 8102, parent: occupied.rootTilingContainer)
        let project = createWorkspaceProject()
        config.persistentWorkspaces = ["spare"]
        Workspace.reconcileWorkspaceState()
        config.persistentWorkspaces = []
        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(Workspace.all.count, 2)
        XCTAssertTrue(Workspace.all.contains(occupied))
        XCTAssertEqual(Workspace.all.filter { $0.projectId == project.id }.count, 1)
    }

    func testRequestedTemporaryBlankSurvivesUntilLeaving() {
        let occupied = focus.workspace
        _ = TestWindow.new(id: 8103, parent: occupied.rootTilingContainer)
        let blank = createBlankWorkspace(projectId: occupied.projectId, monitor: mainMonitor)
        _ = blank.focusWorkspace()
        Workspace.reconcileWorkspaceState()
        XCTAssertTrue(Workspace.all.contains(blank))
        _ = occupied.focusWorkspace()
        Workspace.reconcileWorkspaceState()
        XCTAssertFalse(Workspace.all.contains(blank))
    }

    func testHiddenAndMinimizedWindowsKeepTheirWorkspaces() {
        let hidden = Workspace.get(byName: "hidden")
        _ = TestWindow.new(id: 8104, parent: hidden.macOsNativeHiddenAppsWindowsContainer)
        let minimized = Workspace.get(byName: "minimized")
        let window = TestWindow.new(id: 8105, parent: macosMinimizedWindowsContainer)
        window.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: minimized.name)
        Workspace.reconcileWorkspaceState()
        XCTAssertTrue(Workspace.all.contains(hidden))
        XCTAssertTrue(Workspace.all.contains(minimized))
    }

    func testEachDisplayHasADistinctWorkspaceWithoutPersistentSlots() {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let first = TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "First", rect: rect, visibleRect: rect, isMain: true)
        let secondRect = rect.copy(\.topLeftX, 1920)
        let second = TestMonitor(monitorAppKitNsScreenScreensId: 2, name: "Second", rect: secondRect, visibleRect: secondRect, isMain: false)
        setMonitorsForTests([first, second])
        Workspace.reconcileWorkspaceState()
        XCTAssertFalse(first.activeWorkspace === second.activeWorkspace)
        XCTAssertGreaterThanOrEqual(Workspace.all.count, 2)
    }

    func testPendingRestartAssignmentsDoNotKeepExtraEmptyWorkspaces() {
        let occupied = focus.workspace
        _ = TestWindow.new(id: 8201, parent: occupied.rootTilingContainer)
        let stale = Workspace.get(byName: "stale")
        let old = TestWindow.new(id: 8202, parent: stale.rootTilingContainer)
        old.restartIdentity = RestartWindowIdentity(bundleId: "test.app", pid: 123,
            launchDate: Date(timeIntervalSince1970: 1), title: "Old")
        let world = snapshotCurrentFrozenWorld()
        old.unbindFromParent()
        preparePersistedFrozenWorldForStartup(PersistedFrozenWorldEnvelope(version: 2, world: world, pending: nil))
        isWinMuxRuntimeReady = true
        XCTAssertTrue(workspaceHasPendingRestartWindows(stale.name))
        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(Workspace.all, [occupied])
        XCTAssertFalse(workspaceHasPendingRestartWindows(stale.name))
    }

    func testExtraEmptyWorkspaceIsCollectedAfterLeaving() {
        let occupied = focus.workspace
        _ = TestWindow.new(id: 8203, parent: occupied.rootTilingContainer)
        let empty = Workspace.get(byName: "extra")
        _ = empty.focusWorkspace()
        _ = occupied.focusWorkspace()
        Workspace.reconcileWorkspaceState()
        XCTAssertNil(Workspace.existing(byName: empty.name))
        XCTAssertTrue(focus.workspace === occupied)
        XCTAssertTrue(mainMonitor.activeWorkspace === occupied)
    }
}
