@testable import AppBundle
import Common
import XCTest

@MainActor
final class PersistentWorkspaceConfigurationTest: WorkspaceTestCase {
    func testPersistentArrayOrderAndNamesIgnoreOldNamingMetadata() async throws {
        config.persistentWorkspaces = ["7", "1", "Code", "3"]
        materializePersistedWorkspaces()
        _ = Workspace.get(byName: "7").focusWorkspace()
        Workspace.reconcileWorkspaceState()
        for name in config.persistentWorkspaces {
            let workspace = try XCTUnwrap(Workspace.existing(byName: name))
            workspace.markAsAutomaticallyNamed()
            workspace.restoredDisplayIndex = 99
        }
        let spaces = orderedUserFacingWorkspaces(in: workspaceProjectDefaultId)
        XCTAssertEqual(spaces.count, 4)
        XCTAssertEqual(spaces.prefix(4).map(\.name), ["7", "1", "Code", "3"])
        XCTAssertEqual(spaces.map { workspaceDisplayName($0.name) },
            ["Workspace 7", "Workspace 1", "Code", "Workspace 3"])
        let rows = await buildWorkspaceSidebarWorkspaceViewModels(currentFocus: focus, workspaceLabels: [:], availableMonitors: monitors)
        XCTAssertEqual(rows.filter { $0.projectId == workspaceProjectDefaultId }.map(\.displayName),
            ["Workspace 7", "Workspace 1", "Code", "Workspace 3"])
        for _ in 0..<3 { Workspace.reconcileWorkspaceState() }
        XCTAssertEqual(orderedUserFacingWorkspaces(in: workspaceProjectDefaultId).map(\.id), spaces.map(\.id))
        try renameWorkspaceForSidebar(workspaceName: "1", displayName: "Browser")
        try renameWorkspaceForSidebar(workspaceName: "Code", displayName: "IDE")
        XCTAssertEqual(workspaceDisplayName("1"), "Browser")
        XCTAssertEqual(workspaceDefaultDisplayName("1"), "Workspace 1")
        XCTAssertEqual(workspaceDisplayName("Code"), "IDE")
        try resetWorkspaceSidebarName(workspaceName: "Code")
        XCTAssertEqual(workspaceDisplayName("Code"), "Code")
    }

    func testAdjacentAutomaticSlotUsesFirstUnreservedNumber() throws {
        config.persistentWorkspaces = ["1", "3", "5", "7"]
        Workspace.reconcileWorkspaceState()
        let current = try XCTUnwrap(Workspace.existing(byName: "1"))
        _ = current.focusWorkspace()
        XCTAssertEqual(nextAdjacentWorkspaceDisplayIndex(current: current), 2)
        let automatic = try XCTUnwrap(createAdjacentTransientBlankWorkspaceIfAllowed(named: "2", from: current))
        _ = automatic.focusWorkspace()
        XCTAssertEqual(workspaceDisplayName(automatic.name), "Workspace 2")
    }

    func testSparsePersistentNumbersAndAutomaticGapsResolveForFocusAndMoves() async throws {
        config.persistentWorkspaces = ["1", "3", "5", "7"]
        Workspace.reconcileWorkspaceState()
        let added = createBlankWorkspace(projectId: workspaceProjectDefaultId, monitor: mainMonitor)
        _ = TestWindow.new(id: 9819, parent: added.rootTilingContainer)
        for number in [1, 2, 3, 5, 7] {
            let expected = try XCTUnwrap(orderedUserFacingWorkspaces(in: workspaceProjectDefaultId).first {
                workspacePresentationDisplayIndex($0) == number
            })
            let result = try await parseCommand("workspace \(number)").cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertTrue(focus.workspace === expected)
        }
        let dynamic = try XCTUnwrap(orderedUserFacingWorkspaces(in: workspaceProjectDefaultId).first { !$0.isConfiguredPersistent })
        let source = try XCTUnwrap(Workspace.existing(byName: "7"))
        let window = TestWindow.new(id: 9820, parent: source.rootTilingContainer)
        _ = source.focusWorkspace()
        let moved = try await parseCommand("move-node-to-workspace 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(moved.exitCode, 0)
        XCTAssertTrue(window.nodeWorkspace === dynamic)
        Workspace.reconcileWorkspaceState()
        XCTAssertTrue(config.persistentWorkspaces.allSatisfy { Workspace.existing(byName: $0)?.isConfiguredPersistent == true })
        XCTAssertTrue(window.nodeWorkspace === dynamic)
    }

    func testPersistentEmptySlotsSurviveWithoutAMinimum() {
        config.persistentWorkspaces = ["Browser", "Code"]
        materializePersistedWorkspaces()
        _ = Workspace.get(byName: "Browser").focusWorkspace()
        Workspace.reconcileWorkspaceState()
        XCTAssertEqual(orderedUserFacingWorkspaces(in: workspaceProjectDefaultId).map(\.name), ["Browser", "Code"])
        XCTAssertTrue(Workspace.all.allSatisfy(\.isEffectivelyEmpty))
    }

    func testNewPersistentSlotsSeedMainWhileUserFocusesSecondary() {
        let fixture = WorkspaceNavigationFixture()
        defer { fixture.cleanUp() }
        _ = fixture.spaces[1].focusWorkspace()
        config.persistentWorkspaces = ["Code"]
        materializePersistedWorkspaces()
        XCTAssertEqual(Workspace.existing(byName: "Code")?.assignedMonitor?.rect.topLeftCorner,
            fixture.displays[0].rect.topLeftCorner)
        XCTAssertTrue(focus.workspace === fixture.spaces[1])
    }

    func testSavingAppearancePreservesPersistentArrayAndComments() {
        let original = """
        config-version = 2
        persistent-workspaces = [
            "7", # primary task
            "Code"
        ]
        """
        let updated = applyingSettingsConfigEdits([.init(section: "menu-bar", key: "indicator", renderedValue: "'workspace'")], to: original)
        let parsed = parseConfig(updated)
        XCTAssertTrue(parsed.errors.isEmpty)
        XCTAssertEqual(Array(parsed.config.persistentWorkspaces), ["7", "Code"])
        XCTAssertEqual(parsed.config.menuBar.indicator, .workspace)
        XCTAssertTrue(updated.contains("# primary task"))
    }
}
