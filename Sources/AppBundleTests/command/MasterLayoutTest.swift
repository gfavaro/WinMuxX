@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class MasterLayoutTest: WorkspaceTestCase {
    private func run(_ text: String) async throws -> CmdResult {
        try await XCTUnwrap(parseCommand(text).cmdOrNil).run(.defaultEnv, .emptyStdin)
    }

    func testWorkspaceModesPreserveNestedGroupsAndTabs() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let split = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 0)
        let a = TestWindow.new(id: 74001, parent: split)
        let b = TestWindow.new(id: 74002, parent: split)
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tabGroup, index: 1)
        let c = TestWindow.new(id: 74003, parent: tabs)
        let d = TestWindow.new(id: 74004, parent: tabs)
        let originalRootChildren = root.children
        let originalSplitChildren = split.children
        let originalTabChildren = tabs.children
        _ = c.focusWindow()

        let master = try await run("workspace-layout master")
        XCTAssertEqual(master.exitCode, 0)
        XCTAssertEqual(workspace.arrangement, .master)
        XCTAssertEqual(workspace.masterGroupIndex, 1)
        XCTAssertEqual(root.children, originalRootChildren)
        XCTAssertEqual(split.children, originalSplitChildren)
        XCTAssertEqual(tabs.children, originalTabChildren)
        XCTAssertEqual(tabs.layout, .tabGroup)

        let scrolling = try await run("workspace-layout scrolling")
        XCTAssertEqual(scrolling.exitCode, 0)
        XCTAssertEqual(workspace.arrangement, .scrolling)
        XCTAssertEqual(root.children, originalRootChildren)
        XCTAssertEqual(split.children, originalSplitChildren)
        XCTAssertEqual(tabs.children, originalTabChildren)
        XCTAssertTrue([a, b, c, d].allSatisfy { $0.nodeWorkspace === workspace })
    }

    func testARowMadeInDwindleBecomesTheMasterGroupsWithoutChangingTheTree() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let row = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 0)
        let tabs = TilingContainer(parent: row, adaptiveWeight: 6, .v, .tabGroup, index: 0)
        let helium = TestWindow.new(id: 74201, parent: tabs)
        let excel = TestWindow.new(id: 74202, parent: tabs)
        let remote = TestWindow.new(id: 74203, parent: row, adaptiveWeight: 2272)
        let chat = TestWindow.new(id: 74204, parent: row, adaptiveWeight: 1140)
        _ = remote.focusWindow()

        let master = try await run("workspace-layout master")
        XCTAssertEqual(master.exitCode, 0)
        XCTAssertEqual(root.children, [row] as [TreeNode], "The tree is kept")
        XCTAssertEqual(workspace.workspaceLayoutUnits, [tabs, remote, chat] as [TreeNode], "The row's tiles are the groups")
        XCTAssertTrue(excel.topLevelWorkspaceGroup === tabs)
        XCTAssertEqual(workspace.masterGroupIndex, 1, "The focused window is the main one")
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
        let display = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let frames = workspace.arrangementGroupFrames(in: display, gaps: gaps)
        XCTAssertEqual(frames.count, 3)
        for frame in frames {
            XCTAssertGreaterThan(frame.physical.width, 300, "No group is squeezed: \(frame.physical)")
            XCTAssertLessThanOrEqual(frame.physical.maxX, display.maxX + 1, "No group leaves the display")
        }

        let added = bindingDataForNewTilingWindow(workspace, window: nil)
        XCTAssertTrue(added.parent === row, "A new window joins the groups, not a second root group")
        XCTAssertEqual(added.index, 2)

        let scrolling = try await run("workspace-layout scrolling")
        XCTAssertEqual(scrolling.exitCode, 0)
        XCTAssertEqual(workspace.workspaceLayoutUnits, [row] as [TreeNode], "Scrolling keeps the split as one column")
        XCTAssertEqual(helium.nodeWorkspace, workspace)
    }

    func testUltrawideMainsSitSideBySideWithANarrowStack() async throws {
        let previous = config.master
        defer { config.master = previous }
        let workspace = focus.workspace
        let windows = (0..<4).map { TestWindow.new(id: UInt32(74100 + $0), parent: workspace.rootTilingContainer) }
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout master")
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
        let ultrawide = Rect(topLeftX: 0, topLeftY: 0, width: 3440, height: 1440)
        func frames(_ rect: Rect) -> [UInt32: Rect] {
            Dictionary(uniqueKeysWithValues: workspace.arrangementGroupFrames(in: rect, gaps: gaps).map {
                (($0.node as? Window)?.windowId ?? 0, $0.physical)
            })
        }
        let single = frames(ultrawide)
        XCTAssertEqual(single[74101]?.minX, single[74102]?.minX, "One main: the rest stack in one column")

        config.master.ultrawideMains = 2
        let two = frames(ultrawide)
        let main = try XCTUnwrap(two[74100]), second = try XCTUnwrap(two[74101]), stack = try XCTUnwrap(two[74102])
        XCTAssertEqual(main.height, ultrawide.height, accuracy: 1)
        XCTAssertEqual(second.height, ultrawide.height, accuracy: 1, "The second main is full height too")
        XCTAssertEqual(main.width, second.width, accuracy: 2)
        XCTAssertLessThan(main.maxX, second.minX + 1)
        XCTAssertGreaterThan(stack.minX, second.maxX - 1, "The stack is the narrow column on the far side")
        XCTAssertLessThan(stack.width, main.width)
        XCTAssertEqual(two[74103]?.minX, stack.minX)

        let ordinary = frames(Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
        XCTAssertEqual(ordinary[74101]?.minX, ordinary[74102]?.minX, "A 16:9 display keeps one main")

        windows[2].unbindFromParent()
        windows[3].unbindFromParent()
        let pair = frames(ultrawide)
        XCTAssertEqual(try XCTUnwrap(pair[74100]).width, try XCTUnwrap(pair[74101]).width, accuracy: 2, "Two windows share the screen")
        XCTAssertFalse(parseConfig("[master]\nultrawide-mains = 3").errors.isEmpty)
        XCTAssertEqual(parseConfig("[master]\nultrawide-mains = 2").config.master.ultrawideMains, 2)
    }

    func testMasterPromotionChangesWorkspaceSelectionWithoutMovingNodes() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let firstGroup = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 0)
        let first = TestWindow.new(id: 74101, parent: firstGroup)
        let secondGroup = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 1)
        let second = TestWindow.new(id: 74102, parent: secondGroup)
        workspace.arrangement = .master
        workspace.masterGroupIndex = 0
        let promotion = try await run("swap-with-master --window-id \(second.windowId)")
        XCTAssertEqual(promotion.exitCode, 0)
        XCTAssertEqual(workspace.masterGroupIndex, 1)
        XCTAssertTrue(first.parent === firstGroup)
        XCTAssertTrue(second.parent === secondGroup)
        XCTAssertEqual(root.children, [firstGroup, secondGroup])
    }

    func testScrollingMetricsUseIndependentWidthsAndCenterSelection() throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let windows = (0..<3).map { TestWindow.new(id: UInt32(74200 + $0), parent: root) }
        root.children[0].scrollingColumnWidth = 0.25
        root.children[1].scrollingColumnWidth = 0.5
        root.children[2].scrollingColumnWidth = 0.75
        workspace.arrangement = .scrolling
        let metrics = workspace.scrollingMetrics
        XCTAssertEqual(metrics.columns.count, 3)
        XCTAssertEqual(metrics.columns.map(\.node), root.children)
        XCTAssertGreaterThan(metrics.columns[1].start, metrics.columns[0].start)
        XCTAssertGreaterThan(metrics.columns[2].width, metrics.columns[1].width)
        _ = windows[2].focusWindow()
        workspace.centerFocusedScrollingColumn()
        XCTAssertEqual(workspace.scrollingOffset, metrics.offsetRange.upperBound, accuracy: 1)
        XCTAssertEqual(metrics.columns[2].start + metrics.columns[2].width - workspace.scrollingOffset,
                       metrics.areaWidth, accuracy: 1)
    }

    func testScrollingWorkspaceLayoutKeepsGroupsAndUsesStoredWidthAndOffset() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let windows = (0..<4).map { TestWindow.new(id: UInt32(74300 + $0), parent: root) }
        root.children.forEach { $0.scrollingColumnWidth = 0.5 }
        workspace.arrangement = .scrolling
        workspace.lastScrollingFocusWindowId = windows[0].windowId
        workspace.scrollingOffset = 350
        let groups = root.children
        try await workspace.layoutWorkspace()
        XCTAssertEqual(root.children, groups)
        XCTAssertTrue(windows.allSatisfy { $0.lastAppliedLayoutVirtualRect != nil })
        XCTAssertTrue(workspace.scrollingMetrics.offsetRange.contains(workspace.scrollingOffset))
    }

    func testWorkspaceModeAndColumnWidthSurviveFrozenWorldRoundTrip() throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let one = TestWindow.new(id: 74401, parent: root)
        TestWindow.new(id: 74402, parent: root)
        one.scrollingColumnWidth = 0.3333
        workspace.arrangement = .scrolling
        workspace.scrollingOffset = 120
        let snapshot = FrozenWorkspace(workspace)
        let decoded = try JSONDecoder().decode(FrozenWorkspace.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.arrangement, .scrolling)
        XCTAssertEqual(decoded.scrollingOffset, 120)
        guard case .window(let saved) = try XCTUnwrap(decoded.rootTilingNode.children.first) else {
            return XCTFail("Expected a saved top-level window")
        }
        XCTAssertEqual(saved.scrollingColumnWidth, 0.3333)
    }

    func testLegacyMasterSnapshotUnwrapsGeneratedStackAndRetainsGroups() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .master
        root.masterRatio = 0.72
        let primaryGroup = TilingContainer(parent: root, adaptiveWeight: 0.6, .h, .tiles, index: 0)
        let primary = TestWindow.new(id: 74410, parent: primaryGroup)
        let generatedStack = TilingContainer(parent: root, adaptiveWeight: 0.4, .v, .tiles, index: 1)
        generatedStack.isMasterStack = true
        let tabs = TilingContainer(parent: generatedStack, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let one = TestWindow.new(id: 74411, parent: tabs)
        let two = TestWindow.new(id: 74412, parent: tabs)
        let anotherGroup = TilingContainer(parent: generatedStack, adaptiveWeight: 1, .h, .tiles, index: 1)
        let other = TestWindow.new(id: 74413, parent: anotherGroup)
        let frozen = FrozenWorkspace(workspace)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(frozen)) as? [String: Any])
        json.removeValue(forKey: "arrangement")
        json.removeValue(forKey: "scrollingOffset")
        json.removeValue(forKey: "masterGroupIndex")
        json.removeValue(forKey: "masterStackLayout")
        let legacy = try JSONDecoder().decode(FrozenWorkspace.self, from: JSONSerialization.data(withJSONObject: json))
        let ids = Set([primary, one, two, other].map(\.windowId))
        let world = FrozenWorld(workspaces: [legacy], monitors: [], windowIds: ids)
        let restored = try await restoreFrozenWorldIfNeeded(world, newlyDetectedWindow: primary, restoreVisibleWorkspaces: false)
        XCTAssertTrue(restored)
        XCTAssertEqual(workspace.arrangement, .master)
        XCTAssertEqual(workspace.masterRatio, 0.72)
        XCTAssertEqual(workspace.rootTilingContainer.layout, .dwindle)
        XCTAssertFalse(workspace.rootTilingContainer.children.contains { ($0 as? TilingContainer)?.isMasterStack == true })
        let restoredTabs = try XCTUnwrap(workspace.rootTilingContainer.allTabbedContainersRecursive.first)
        XCTAssertEqual(restoredTabs.layout, .tabGroup)
        XCTAssertEqual(restoredTabs.children.filterIsInstance(of: Window.self), [one, two])
        XCTAssertTrue([primary, one, two, other].allSatisfy { $0.nodeWorkspace === workspace })
    }

    func testScrollingConfigurationAndCommandsValidateAndApply() async throws {
        let parsed = parseConfig("""
            [scrolling]
            column-width = 0.49
            width-presets = [0.25, 0.5, 1.0]
            gesture-enabled = true
            gesture-sensitivity = 1.2
            minimap-enabled = true
            [workspace.Code]
            layout = 'scrolling'
            """)
        XCTAssertTrue(parsed.errors.isEmpty, parsed.errors.map(\.description).joined(separator: "\n"))
        // Root layouts from before arrangements (tiles, accordion, tab-group) stay valid for upgrades.
        XCTAssertTrue(parseConfig("[workspace.Code]\nlayout = 'tiles'").errors.isEmpty)
        for invalid in ["[scrolling]\ncolumn-width = 0", "[scrolling]\nwidth-presets = [0.5, 0.25]", "[workspace.Code]\nlayout = 'spiral'"] {
            XCTAssertFalse(parseConfig(invalid).errors.isEmpty, invalid)
        }
        let workspace = focus.workspace
        workspace.arrangement = .scrolling
        let window = TestWindow.new(id: 74501, parent: workspace.rootTilingContainer)
        _ = window.focusWindow()
        let result = try await run("scrolling-width next")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNotNil(window.scrollingColumnWidth)
        let center = try await run("scrolling-center")
        XCTAssertEqual(center.exitCode, 0)
    }

    func testDefaultRootLayoutMasterStillGivesAMasterWorkspace() async throws {
        config.defaultRootContainerLayout = .master
        let workspace = Workspace.get(byName: "fresh-master")
        let windows = (0..<3).map { TestWindow.new(id: UInt32(8400 + $0), parent: workspace.rootTilingContainer) }
        XCTAssertTrue(windows[0].focusWindow())
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.arrangement, .master)
        XCTAssertEqual(workspace.rootTilingContainer.layout, .tiles)
        let swap = try await XCTUnwrap(parseCommand("swap-with-master").unwrap().0).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(swap.exitCode, 0, swap.stderr.joined())
    }
}
