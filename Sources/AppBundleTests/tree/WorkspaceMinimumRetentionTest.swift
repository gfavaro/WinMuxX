@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WorkspaceMinimumRetentionTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws { setUpWorkspacesForTests() }

    func testMinimumCreatesVisibleSidebarSlotsWithoutChangingFocus() {
        let focused = focus.workspace
        config.minimumWorkspaceCount = 4
        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(Workspace.all.count, 4)
        XCTAssertTrue(focus.workspace === focused)
        XCTAssertTrue(Workspace.all.allSatisfy { isUserFacingWorkspace($0) })
        XCTAssertTrue(Workspace.all.allSatisfy { $0.projectId == workspaceProjectDefaultId })
        let identities = Set(Workspace.all.map(\.id))
        for _ in 0..<3 { Workspace.reconcileWorkspaceState() }
        XCTAssertEqual(Set(Workspace.all.map(\.id)), identities)
    }

    func testExistingEmptyWorkspacesAreReused() {
        let one = Workspace.get(byName: "reuse-one")
        let two = Workspace.get(byName: "reuse-two")
        config.minimumWorkspaceCount = 3
        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(Workspace.all.count, 3)
        XCTAssertTrue(Workspace.all.contains(one))
        XCTAssertTrue(Workspace.all.contains(two))
    }

    func testGlobalCountAndReductionKeepProjectAndOccupiedWorkspaces() {
        let occupied = focus.workspace
        let window = TestWindow.new(id: 8101, parent: occupied.rootTilingContainer)
        let project = createWorkspaceProject()
        config.minimumWorkspaceCount = 4
        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(Workspace.all.count, 4)
        XCTAssertEqual(Workspace.all.filter { $0.projectId == project.id }.count, 1)
        config.minimumWorkspaceCount = 0
        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(Workspace.all.count, 2)
        XCTAssertTrue(Workspace.all.contains(occupied))
        XCTAssertTrue(window.nodeWorkspace === occupied)
        XCTAssertEqual(Workspace.all.filter { $0.projectId == project.id }.count, 1)
    }

    func testDeletingRetainedSlotReplenishesMinimum() throws {
        config.minimumWorkspaceCount = 3
        Workspace.reconcileWorkspaceState()
        let removed = try XCTUnwrap(Workspace.all.first { !$0.isVisible })
        try deleteWorkspace(removed)
        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(Workspace.all.count, 3)
        XCTAssertFalse(Workspace.all.contains { $0.id == removed.id })
    }

    func testLifecycleWindowsRemainProtectedWhenMinimumIsDisabled() {
        let hidden = Workspace.get(byName: "hidden")
        _ = TestWindow.new(id: 8102, parent: hidden.macOsNativeHiddenAppsWindowsContainer)
        let minimized = Workspace.get(byName: "minimized")
        let window = TestWindow.new(id: 8103, parent: macosMinimizedWindowsContainer)
        window.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: minimized.name)
        config.minimumWorkspaceCount = 0
        Workspace.reconcileWorkspaceState()
        XCTAssertTrue(Workspace.all.contains(hidden))
        XCTAssertTrue(Workspace.all.contains(minimized))
    }

    func testMonitorGuaranteesCanExceedConfiguredMinimum() {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let first = TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "First", rect: rect, visibleRect: rect, isMain: true)
        let secondRect = rect.copy(\.topLeftX, 1920)
        let second = TestMonitor(monitorAppKitNsScreenScreensId: 2, name: "Second", rect: secondRect, visibleRect: secondRect, isMain: false)
        setMonitorsForTests([first, second])
        config.minimumWorkspaceCount = 1
        Workspace.reconcileWorkspaceState()
        XCTAssertFalse(first.activeWorkspace === second.activeWorkspace)
        XCTAssertGreaterThanOrEqual(Workspace.all.count, 2)
    }

    func testParsingAndExplicitMinimumOverrideLegacyNames() {
        for value in ["0", "1", "7"] {
            XCTAssertTrue(parseConfig("minimum-workspace-count = " + value).errors.isEmpty)
        }
        for value in ["-1", "1.5", "true", "'3'"] {
            XCTAssertFalse(parseConfig("minimum-workspace-count = " + value).errors.isEmpty)
        }
        let legacy = parseConfig("config-version = 2\npersistent-workspaces = ['a', 'b', 'c']")
        XCTAssertEqual(legacy.config.effectiveMinimumWorkspaceCount, 3)
        config = parseConfig("config-version = 2\nminimum-workspace-count = 1\npersistent-workspaces = ['legacy']").config
        materializePersistedWorkspaces()
        XCTAssertNil(Workspace.existing(byName: "legacy"))
        XCTAssertEqual(config.effectiveMinimumWorkspaceCount, 1)
    }
}
