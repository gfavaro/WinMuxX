@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WorkspaceArrangementRegressionTest: WorkspaceTestCase {
    private func run(_ text: String) async throws -> CmdResult {
        try await XCTUnwrap(parseCommand(text).cmdOrNil).run(.defaultEnv, .emptyStdin)
    }

    func testMasterPaneCanStillBeResized() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        root.changeOrientation(.h)
        let a = TestWindow.new(id: 94611, parent: root)
        TestWindow.new(id: 94612, parent: root)
        workspace.arrangement = .master
        _ = a.focusWindow()
        try await workspace.layoutWorkspace()
        let before = try XCTUnwrap(a.lastAppliedLayoutPhysicalRect).width
        _ = try await run("resize width +100")
        try await workspace.layoutWorkspace()
        XCTAssertGreaterThan(try XCTUnwrap(a.lastAppliedLayoutPhysicalRect).width, before)
    }

    func testMasterPanesAndNavigationFollowAllFourSides() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let primary = TestWindow.new(id: 94615, parent: root)
        let other = TestWindow.new(id: 94616, parent: root)
        workspace.arrangement = .master
        workspace.masterRatio = 0.7
        for (side, direction): (MasterSide, CardinalDirection) in [(.left, .right), (.right, .left), (.top, .down), (.bottom, .up)] {
            config.master.side = side
            _ = primary.focusWindow()
            try await workspace.layoutWorkspace()
            let available = workspaceTilingRect(workspace)
            for window in [primary, other] {
                let frame = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
                XCTAssertGreaterThanOrEqual(frame.minX, available.minX)
                XCTAssertGreaterThanOrEqual(frame.minY, available.minY)
                XCTAssertLessThanOrEqual(frame.maxX, available.maxX + 0.01)
                XCTAssertLessThanOrEqual(frame.maxY, available.maxY + 0.01)
            }
            XCTAssertTrue(dwindleDirectionalFocusTarget(from: primary, direction: direction) === other)
        }
    }

    func testNewGroupDoesNotChangeExistingMaster() throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let a = TestWindow.new(id: 94621, parent: root)
        TestWindow.new(id: 94622, parent: root)
        let originalMaster = TestWindow.new(id: 94623, parent: root)
        workspace.arrangement = .master
        workspace.masterGroupIndex = 2
        _ = a.focusWindow()
        let binding = bindingDataForNewTilingWindow(workspace, window: nil)
        let inserted = TestWindow.new(id: 94624, parent: workspace)
        inserted.unbindFromParent()
        inserted.bind(to: binding.parent, adaptiveWeight: 1, index: binding.index)
        workspace.normalizeMasterLayout()
        XCTAssertTrue(workspace.workspaceLayoutUnits[workspace.masterGroupIndex] === originalMaster)
        a.unbindFromParent()
        workspace.normalizeMasterLayout()
        XCTAssertTrue(workspace.workspaceLayoutUnits[workspace.masterGroupIndex] === originalMaster)
    }

    func testRefreshNormalizationPreservesTopLevelGroups() throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        root.dwindleOrientation = .h
        root.dwindleChildRatios = [0.5, 0.5]
        let split = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 0)
        TestWindow.new(id: 94641, parent: split)
        TestWindow.new(id: 94642, parent: split)
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tabGroup, index: 1)
        TestWindow.new(id: 94643, parent: tabs)
        TestWindow.new(id: 94644, parent: tabs)
        let splitChildren = split.children
        let tabChildren = tabs.children
        for mode in [WorkspaceLayoutName.master, .dwindle] {
            workspace.arrangement = mode
            workspace.normalizeContainers()
            XCTAssertTrue(workspace.rootTilingContainer === root)
            XCTAssertEqual(workspace.rootTilingContainer.children, [split, tabs])
            XCTAssertEqual(split.layout, .tiles)
            XCTAssertEqual(split.children, splitChildren)
            XCTAssertEqual(tabs.layout, .tabGroup)
            XCTAssertEqual(tabs.children, tabChildren)
        }
    }

    func testMasterRatioAndGroupProtectionSurviveRestartInDwindleMode() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        root.dwindleOrientation = .h
        root.dwindleChildRatios = [0.5, 0.5]
        let primary = TestWindow.new(id: 94651, parent: root)
        let split = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 1)
        let b = TestWindow.new(id: 94652, parent: split)
        let c = TestWindow.new(id: 94653, parent: split)
        workspace.arrangement = .master
        _ = primary.focusWindow()
        try await workspace.layoutWorkspace()
        _ = try await run("resize width +100")
        let ratio = try XCTUnwrap(workspace.masterRatio)
        workspace.arrangement = .dwindle
        let frozen = try JSONDecoder().decode(FrozenWorkspace.self, from: JSONEncoder().encode(FrozenWorkspace(workspace)))
        let restored = try await restoreFrozenWorldIfNeeded(
            FrozenWorld(workspaces: [frozen], monitors: [], windowIds: Set([primary, b, c].map(\.windowId))),
            newlyDetectedWindow: primary, restoreVisibleWorkspaces: false)
        XCTAssertTrue(restored)
        XCTAssertEqual(workspace.arrangement, .dwindle)
        XCTAssertEqual(workspace.masterRatio, ratio)
        XCTAssertTrue(workspace.preservesTopLevelGroups)
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.children.count, 2)
        let restoredSplit = try XCTUnwrap(workspace.rootTilingContainer.children.last as? TilingContainer)
        XCTAssertEqual(restoredSplit.layout, .tiles)
        XCTAssertEqual(restoredSplit.children, [b, c])
    }

}
