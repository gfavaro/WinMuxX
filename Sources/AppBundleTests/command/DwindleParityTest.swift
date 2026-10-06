@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class DwindleParityTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.defaultRootContainerOrientation = .auto
    }

    private func root() -> TilingContainer {
        let root = focus.workspace.rootTilingContainer
        root.layout = .dwindle
        return root
    }

    func testClosingCollapsesItsSplitAndInsertionSplitsDonor() {
        let root = root()
        let first = TestWindow.new(id: 18001, parent: root)
        let middle = TestWindow.new(id: 18002, parent: root)
        let last = TestWindow.new(id: 18003, parent: root)
        root.setDwindleSplitRatio(0.6, at: 0)
        root.setDwindleSplitRatio(0.25, at: 1)
        middle.unbindFromParent()
        XCTAssertEqual(root.dwindleSplitRatio(at: 0), 0.6, accuracy: 0.0001)
        let inserted = TestWindow.new(id: 18004, parent: focus.workspace)
        inserted.bind(to: root, adaptiveWeight: 1, index: 1)
        XCTAssertEqual(root.children, [first, inserted, last])
        let shares = root.dwindleShares(count: 3)
        for (share, expected) in zip(shares, [0.3, 0.3, 0.4]) {
            XCTAssertEqual(share, expected, accuracy: 0.0001)
        }
    }

    func testRemovingAnyOfThreeDefaultWindowsLeavesEqualTiles() async throws {
        for removedIndex in 0..<3 {
            setUpWorkspacesForTests()
            config.defaultRootContainerOrientation = .auto
            let workspace = focus.workspace
            let root = root()
            let windows = (0..<3).map { TestWindow.new(id: UInt32(18100 + $0), parent: root) }
            windows[removedIndex].unbindFromParent()
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
            let remaining = windows.enumerated().filter { $0.offset != removedIndex }.map(\.element)
            let a = remaining[0].lastAppliedLayoutPhysicalRect.orDie()
            let b = remaining[1].lastAppliedLayoutPhysicalRect.orDie()
            XCTAssertEqual(a.width, b.width, accuracy: 1)
            XCTAssertEqual(a.height, b.height, accuracy: 1)
            XCTAssertEqual(root.dwindleSplitRatio(at: 0), 0.5)
        }
    }

    func testMovingWindowToAnotherWorkspaceCollapsesOnlyItsSplit() async throws {
        let workspace = focus.workspace
        let root = root()
        let windows = (0..<4).map { TestWindow.new(id: UInt32(18110 + $0), parent: root) }
        root.setDwindleSplitRatio(0.6, at: 0)
        root.setDwindleSplitRatio(0.3, at: 1)
        root.setDwindleSplitRatio(0.7, at: 2)
        let destination = Workspace.get(byName: "destination")
        windows[1].bind(to: destination.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(root.dwindleShares(count: root.children.count), [0.6, 0.4])
        let branch = root.children[1] as? TilingContainer
        XCTAssertEqual(branch?.dwindleChildRatios?.first ?? 0, 0.7, accuracy: 0.000001)
        XCTAssertEqual(branch?.dwindleChildRatios?.last ?? 0, 0.3, accuracy: 0.000001)
        XCTAssertTrue(windows[1].nodeWorkspace === destination)
        XCTAssertEqual(root.allLeafWindowsRecursive.count, 3)
    }

    func testWrappingAndNormalizingPreserveDwindleSlot() async throws {
        let root = root()
        let first = TestWindow.new(id: 18010, parent: root)
        let second = TestWindow.new(id: 18011, parent: root)
        root.setDwindleSplitRatio(0.7, at: 0)
        _ = first.focusWindow()
        try await focus.workspace.layoutWorkspace()
        let original = first.lastAppliedLayoutPhysicalRect
        let binding = bindingDataForNewTilingWindow(focus.workspace, window: nil)
        let added = TestWindow.new(id: 18012, parent: binding.parent)
        XCTAssertEqual(root.dwindleSplitRatio(at: 0), 0.7)
        XCTAssertTrue(first.parent === added.parent)
        added.unbindFromParent()
        config.enableNormalizationFlattenContainers = true
        focus.workspace.normalizeContainers()
        try await focus.workspace.layoutWorkspace()
        XCTAssertEqual(root.children, [first, second])
        XCTAssertEqual(root.dwindleSplitRatio(at: 0), 0.7)
        XCTAssertEqual(first.lastAppliedLayoutPhysicalRect, original)
    }

    func testInsertionReusesMatchingPhysicalAxisAndPreservesTabs() async throws {
        let root = root()
        let tiles = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 0)
        let first = TestWindow.new(id: 18020, parent: tiles)
        TestWindow.new(id: 18021, parent: tiles)
        _ = first.focusWindow()
        first.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 900, height: 300)
        first.lastAppliedLayoutVirtualRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 800)
        let binding = bindingDataForNewTilingWindow(focus.workspace, window: nil)
        XCTAssertTrue(binding.parent === tiles)
        XCTAssertEqual(binding.index, 1)
        let tabs = TilingContainer(parent: tiles, adaptiveWeight: 1, .v, .tabGroup, index: 1)
        let tab = TestWindow.new(id: 18022, parent: tabs)
        TestWindow.new(id: 18023, parent: tabs)
        config.autoAddNewWindowsToTabGroup = false
        _ = tab.focusWindow()
        tabs.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 800, height: 300)
        let tabBinding = bindingDataForNewTilingWindow(focus.workspace, window: nil)
        XCTAssertTrue(tabBinding.parent === tiles)
        XCTAssertEqual(tabs.children.count, 2)
    }

    func testExplicitAxisAutoAndPersistence() async throws {
        let root = root()
        let first = TestWindow.new(id: 18030, parent: root)
        TestWindow.new(id: 18031, parent: root)
        _ = first.focusWindow()
        let vertical = try await parseCommand("layout vertical").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(vertical.exitCode, 0)
        XCTAssertEqual(root.dwindleOrientation, .v)
        let gaps = ResolvedGaps(gaps: .zero, monitor: focus.workspace.workspaceMonitor)
        let wide = Rect(topLeftX: 0, topLeftY: 0, width: 1600, height: 600)
        XCTAssertEqual(root.dwindleChildFrames(in: wide, gaps: gaps)[0].height, 300)
        let snapshot = snapshotCurrentFrozenWorld()
        let restored = try await restoreFrozenWorldIfNeeded(snapshot, newlyDetectedWindow: first)
        XCTAssertTrue(restored)
        XCTAssertEqual(focus.workspace.rootTilingContainer.dwindleOrientation, .v)
        let automatic = try await parseCommand("layout auto").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(automatic.exitCode, 0)
        XCTAssertNil(focus.workspace.rootTilingContainer.dwindleOrientation)
        XCTAssertEqual(focus.workspace.rootTilingContainer.dwindleChildFrames(in: wide, gaps: gaps)[0].width, 800)
    }

    func testNestedMinimumIncludesTabsAndActualGaps() {
        config.windowTabs.enabled = true
        let root = root()
        root.dwindleOrientation = .h
        let first = TestWindow.new(id: 18040, parent: root)
        first.testMinimumSize = CGSize(width: 300, height: 100)
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tabGroup, index: 1)
        let tab = TestWindow.new(id: 18041, parent: tabs)
        tab.testMinimumSize = CGSize(width: 400, height: 200)
        TestWindow.new(id: 18042, parent: tabs)
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 600)
        let gaps = ResolvedGaps(gaps: .zero, monitor: focus.workspace.workspaceMonitor)
        XCTAssertEqual(root.minimumLayoutExtent(along: .h, gaps: gaps, rect: rect), 706)
        XCTAssertEqual(root.minimumLayoutExtent(along: .v, gaps: gaps, rect: rect), 200 + resolvedWindowTabBarHeight() + 3)
        root.setDwindleSplitRatio(0.9, at: 0)
        let frames = root.dwindleChildFrames(in: rect, gaps: gaps)
        XCTAssertEqual(frames[1].width, 406)
        XCTAssertEqual(frames[0].width, 594)
    }

    func testTileMinimumIsContentSizeAfterGapsAndPreviewMatches() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let first = TestWindow.new(id: 18050, parent: root)
        let second = TestWindow.new(id: 18051, parent: root)
        first.testMinimumSize = CGSize(width: 1200, height: 100)
        first.setWeight(.h, 1)
        second.setWeight(.h, 1000)
        try await workspace.layoutWorkspace()
        XCTAssertGreaterThanOrEqual(first.lastAppliedLayoutPhysicalRect.orDie().width, 1200)
        let geometry = dwindleGeometry(in: workspace, physical: true)
        XCTAssertEqual(geometry[ObjectIdentifier(first)], first.lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(geometry[ObjectIdentifier(second)], second.lastAppliedLayoutPhysicalRect)
    }

    func testMoveEntersNeighborAndLeavesNestedContainerKeepingTabGroup() async throws {
        let root = root()
        let moving = TestWindow.new(id: 18060, parent: root)
        let tiles = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: 1)
        let upper = TestWindow.new(id: 18061, parent: tiles)
        let lower = TestWindow.new(id: 18062, parent: tiles)
        _ = moving.focusWindow()
        try await focus.workspace.layoutWorkspace()
        let result = try await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(moving.parent === upper.parent)
        XCTAssertFalse(moving.parent === root)
        XCTAssertTrue(lower.parent === focus.workspace.rootTilingContainer)
        XCTAssertEqual(focus.workspace.rootTilingContainer.dwindleOrientation, .v)
        XCTAssertTrue(focus.windowOrNil === moving)
        try await focus.workspace.layoutWorkspace()
        let leaving = try await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(leaving.exitCode, 0)
        XCTAssertTrue(moving.parent === focus.workspace.rootTilingContainer)
        XCTAssertEqual(focus.workspace.rootTilingContainer.layout, .dwindle)
    }

    func testFlattenResetsRatiosPreservesOrderFloatingAndFocus() async throws {
        let root = root()
        let first = TestWindow.new(id: 18070, parent: root)
        let tiles = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 1)
        let second = TestWindow.new(id: 18071, parent: tiles)
        let third = TestWindow.new(id: 18072, parent: tiles)
        let floating = TestWindow.new(id: 18073, parent: focus.workspace)
        root.setDwindleSplitRatio(0.75, at: 0)
        root.dwindleOrientation = .v
        _ = second.focusWindow()
        let result = try await parseCommand("flatten-workspace-tree").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(root.children, [first, second, third])
        XCTAssertTrue(floating.parent === focus.workspace)
        XCTAssertTrue(focus.windowOrNil === second)
        XCTAssertTrue(root.mostRecentWindowRecursive === second)
        XCTAssertTrue(root.dwindleSplitRatios.isEmpty)
        XCTAssertNil(root.dwindleOrientation)
    }
    func testCornerResizeProcessesAxesSequentiallyAndSkipsFlippedSplit() async throws {
        let root = root()
        TestWindow.new(id: 18080, parent: root)
        TestWindow.new(id: 18081, parent: root)
        let last = TestWindow.new(id: 18082, parent: root)
        try await focus.workspace.layoutWorkspace()
        let original = last.lastAppliedLayoutPhysicalRect.orDie()
        let corner = Rect(topLeftX: original.minX - 80, topLeftY: original.minY - 60,
            width: original.width + 80, height: original.height + 60)
        let map = try XCTUnwrap(proposedResizeWeightMap(last, rect: corner))
        XCTAssertEqual(map.dwindleChanges.count, 2)
        let geometry = dwindleGeometry(in: focus.workspace, weightMap: map, physical: true)
        applyResizeWithMouse(last, rect: corner)
        cancelManipulatedWithMouseState()
        try await focus.workspace.layoutWorkspace()
        XCTAssertEqual(last.lastAppliedLayoutPhysicalRect, corner)
        XCTAssertEqual(geometry[ObjectIdentifier(last)], corner)

        root.dwindleSplitRatios = []
        try await focus.workspace.layoutWorkspace()
        let flipped = Rect(topLeftX: original.minX - 400, topLeftY: original.minY - 60,
            width: original.width + 400, height: original.height + 60)
        let flippedMap = try XCTUnwrap(proposedResizeWeightMap(last, rect: flipped))
        XCTAssertEqual(flippedMap.dwindleChanges.count, 1)
        let predicted = dwindleGeometry(in: focus.workspace, weightMap: flippedMap, physical: true)
        applyResizeWithMouse(last, rect: flipped)
        cancelManipulatedWithMouseState()
        try await focus.workspace.layoutWorkspace()
        XCTAssertEqual(predicted[ObjectIdentifier(last)], last.lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(root.dwindleSplitRatio(at: 1), 0.5)
    }

    func testDirectionalFocusTreatsTabsAsOneSlotAndTabCommandsReachHiddenTabs() async throws {
        let root = root()
        let left = TestWindow.new(id: 18090, parent: root)
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tabGroup, index: 1)
        let hidden = TestWindow.new(id: 18091, parent: tabs)
        let active = TestWindow.new(id: 18092, parent: tabs)
        _ = left.focusWindow()
        try await focus.workspace.layoutWorkspace()
        XCTAssertTrue(dwindleDirectionalFocusTarget(from: left, direction: .right) === active)
        XCTAssertNil(dwindleFocusFrames(in: focus.workspace)[hidden.windowId])
        _ = active.focusWindow()
        let result = try await parseCommand("focus tab-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(focus.windowOrNil === hidden)
        XCTAssertTrue(dwindleDirectionalFocusTarget(from: hidden, direction: .left) === left)
    }

    func testPerMonitorGapsPropagateThroughNestedMinimums() {
        let root = root()
        let tiles = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 0)
        let first = TestWindow.new(id: 18100, parent: tiles)
        let second = TestWindow.new(id: 18101, parent: tiles)
        first.testMinimumSize = CGSize(width: 200, height: 100)
        second.testMinimumSize = CGSize(width: 300, height: 100)
        let secondary = TestMonitor(monitorAppKitNsScreenScreensId: 2, name: "secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1200, height: 900),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1200, height: 900), isMain: false)
        let primary = mainMonitor
        setMonitorsForTests([primary, secondary])
        defer { setMonitorsForTests(nil) }
        config.gaps.inner.horizontal = .perMonitor([.init(description: .secondary, value: 40)], default: 8)
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: secondary)
        XCTAssertEqual(gaps.inner.horizontal, 40)
        XCTAssertEqual(tiles.minimumLayoutExtent(along: .h, gaps: gaps, rect: secondary.rect), 540)
    }

    func testNestedAutomaticMinimumUsesAllocatedChildRectangle() {
        let root = root()
        let nested = TilingContainer(parent: root, adaptiveWeight: 1, .h, .dwindle, index: 0)
        let first = TestWindow.new(id: 18110, parent: nested)
        let second = TestWindow.new(id: 18111, parent: nested)
        first.testMinimumSize = CGSize(width: 400, height: 200)
        second.testMinimumSize = CGSize(width: 400, height: 200)
        TestWindow.new(id: 18112, parent: root)
        root.setDwindleSplitRatio(0.1, at: 0)
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1800, height: 1000)
        let gaps = ResolvedGaps(gaps: .zero, monitor: focus.workspace.workspaceMonitor)
        let frames = root.dwindleChildFrames(in: rect, gaps: gaps)
        // The nested child is portrait, so its windows stack and share the same width.
        XCTAssertEqual(frames[0].width, 400)
        let nestedFrames = nested.dwindleChildFrames(in: frames[0], gaps: gaps)
        XCTAssertEqual(nestedFrames.map(\.width), [400, 400])
        XCTAssertEqual(nestedFrames.map(\.height), [500, 500])
    }

    func testCrossParentSwapPreservesBothSlotRatiosAndWholeTabs() {
        let root = root()
        let first = TestWindow.new(id: 18120, parent: root)
        let nested = TilingContainer(parent: root, adaptiveWeight: 1, .h, .dwindle, index: 1)
        let tabs = TilingContainer(parent: nested, adaptiveWeight: 1, .v, .tabGroup, index: 0)
        let tab = TestWindow.new(id: 18121, parent: tabs)
        TestWindow.new(id: 18122, parent: tabs)
        TestWindow.new(id: 18123, parent: nested)
        root.setDwindleSplitRatio(0.65, at: 0)
        nested.setDwindleSplitRatio(0.3, at: 0)
        swapNodes(first, tabs)
        XCTAssertEqual(root.children, [tabs, nested])
        XCTAssertTrue(first.parent === nested)
        XCTAssertTrue(tab.parent === tabs)
        XCTAssertEqual(tabs.children.count, 2)
        XCTAssertEqual(root.dwindleSplitRatio(at: 0), 0.65)
        XCTAssertEqual(nested.dwindleSplitRatio(at: 0), 0.3)
    }

    func testConfiguredOrientationAppliesAtCreationAndLiveReload() {
        config.defaultRootContainerLayout = .dwindle
        config.defaultRootContainerOrientation = .vertical
        let workspace = Workspace.get(byName: "explicit-axis")
        let root = workspace.rootTilingContainer
        XCTAssertEqual(root.dwindleOrientation, .v)
        let previousReady = isWinMuxRuntimeReady
        isWinMuxRuntimeReady = true
        defer { isWinMuxRuntimeReady = previousReady }
        config.defaultRootContainerOrientation = .auto
        applyUpdatedDwindleOrientation(previousOrientation: .vertical)
        XCTAssertNil(root.dwindleOrientation)
        root.dwindleOrientation = .h
        applyUpdatedDwindleOrientation(previousOrientation: .auto)
        XCTAssertEqual(root.dwindleOrientation, .h) // An unrelated reload keeps manual choices.
    }

    func testFocusWrapUsesGeometricEdgeForExplicitVerticalDwindle() async throws {
        let root = root()
        root.dwindleOrientation = .v
        let top = TestWindow.new(id: 18130, parent: root)
        TestWindow.new(id: 18131, parent: root)
        let bottom = TestWindow.new(id: 18132, parent: root)
        _ = bottom.focusWindow()
        try await focus.workspace.layoutWorkspace()
        let result = try await parseCommand("focus --boundaries-action wrap-around-the-workspace down").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(focus.windowOrNil === top)
    }

}
