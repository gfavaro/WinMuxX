@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WorkspaceTabbedArrangementTest: WorkspaceTestCase {
    private func run(_ text: String) async throws -> CmdResult {
        try await XCTUnwrap(parseCommand(text).cmdOrNil).run(.defaultEnv, .emptyStdin)
    }

    /// A workspace with a split and a nested tab group, so returning to Dwindle has a tree to restore.
    private func makeNestedWorkspace() -> (Workspace, [TestWindow], TilingContainer) {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let left = TestWindow.new(id: 29000, parent: root)
        let group = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .h, .tabGroup, index: INDEX_BIND_LAST)
        let tabA = TestWindow.new(id: 29001, parent: group)
        let tabB = TestWindow.new(id: 29002, parent: group)
        return (workspace, [left, tabA, tabB], group)
    }

    func testEveryWindowBecomesATabAndOnlyTheFocusedOneShows() async throws {
        let (workspace, windows, _) = makeNestedWorkspace()
        _ = windows[1].focusWindow()
        let result = try await run("workspace-layout tabbed")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(workspace.arrangement, .tabbed)
        try await workspace.layoutWorkspace()
        let rect = workspaceTilingRect(workspace)
        let shown = try XCTUnwrap(windows[1].lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(shown.topLeftY, workspaceTabbedContentRect(rect).topLeftY, "The window sits under the tab bar")
        XCTAssertEqual(shown.width, rect.width)
        XCTAssertNil(windows[0].lastAppliedLayoutPhysicalRect, "Other windows wait hidden as tabs")
        XCTAssertNil(windows[2].lastAppliedLayoutPhysicalRect)
    }

    func testReturningToDwindleRestoresTheTreeExactly() async throws {
        let (workspace, windows, group) = makeNestedWorkspace()
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout tabbed")
        _ = try await run("workspace-layout dwindle")
        XCTAssertEqual(workspace.arrangement, .dwindle)
        XCTAssertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.elementsEqual(windows, by: ===))
        XCTAssertEqual(group.children.count, 2, "The nested tab group is untouched")
        XCTAssertEqual(group.layout, .tabGroup)
    }

    func testLeftAndRightStepThroughTheTabs() async throws {
        let (_, windows, _) = makeNestedWorkspace()
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout tabbed")
        _ = try await run("focus right")
        XCTAssertTrue(focus.windowOrNil === windows[1])
        _ = try await run("focus right")
        XCTAssertTrue(focus.windowOrNil === windows[2])
        _ = try await run("focus left")
        XCTAssertTrue(focus.windowOrNil === windows[1])
    }

    func testWrapAroundJumpsToTheOppositeEndTab() async throws {
        let (_, windows, _) = makeNestedWorkspace()
        _ = windows[2].focusWindow()
        _ = try await run("workspace-layout tabbed")
        _ = try await run("focus --boundaries-action wrap-around-the-workspace right")
        XCTAssertTrue(focus.windowOrNil === windows[0])
        _ = try await run("focus --boundaries-action wrap-around-the-workspace left")
        XCTAssertTrue(focus.windowOrNil === windows[2])
    }

    func testANestedStripDoesNotSkipTabs() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let strip = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .h, .tabGroup, index: INDEX_BIND_LAST)
        strip.presentsAsStrip = true
        let column = TilingContainer(parent: strip, adaptiveWeight: WEIGHT_AUTO, .v, .tiles, index: INDEX_BIND_LAST)
        let top = TestWindow.new(id: 29100, parent: column)
        let bottom = TestWindow.new(id: 29101, parent: column)
        let next = TestWindow.new(id: 29102, parent: strip)
        _ = top.focusWindow()
        _ = try await run("workspace-layout tabbed")
        _ = try await run("focus right")
        XCTAssertTrue(focus.windowOrNil === bottom, "Right goes to the next tab, not the strip's next column")
        _ = try await run("focus right")
        XCTAssertTrue(focus.windowOrNil === next)
    }

    func testFullscreenHidesTheBarAndTakesTheWholeArea() async throws {
        let (workspace, windows, _) = makeNestedWorkspace()
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout tabbed")
        XCTAssertFalse(workspace.presentsManagedFullscreen)
        windows[0].isFullscreen = true
        XCTAssertTrue(workspace.presentsManagedFullscreen, "The bar is left out while a window is fullscreen")
    }

    func testTheBorderEnclosesTheTabBarAndTheWindow() async throws {
        let (workspace, windows, _) = makeNestedWorkspace()
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout tabbed")
        try await workspace.layoutWorkspace()
        let rect = workspaceTilingRect(workspace)
        let target = try XCTUnwrap(windowBorderTarget(for: windows[0], nativeFrame: .zero))
        XCTAssertEqual(target.frame.minY, rect.topLeftY, "The border starts at the top of the tab bar")
        XCTAssertEqual(target.frame.height, rect.height)
        XCTAssertNil(windowBorderTarget(for: windows[1], nativeFrame: .zero), "Hidden tabs draw no border")
        windows[0].isFullscreen = true
        XCTAssertEqual(windowBorderTarget(for: windows[0], nativeFrame: .zero)?.frame, .zero,
            "In fullscreen there is no bar to enclose")
    }

    func testTabCommandsUseTheFocusedGroupsTabs() async throws {
        let (_, windows, _) = makeNestedWorkspace()
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout tabbed")
        _ = try await run("focus tab-next")
        XCTAssertTrue(focus.windowOrNil === windows[1], "tab-next leaves the left window for the next tab, not a nested group")
        _ = try await run("focus --tab-index 3")
        XCTAssertTrue(focus.windowOrNil === windows[2])
        _ = try await run("focus --boundaries-action wrap-around-the-workspace tab-next")
        XCTAssertTrue(focus.windowOrNil === windows[0])
        let missing = try await run("focus --tab-index 9")
        XCTAssertNotEqual(missing.exitCode, 0)
    }

    func testReorderingTabsLeavesTheTreeAlone() async throws {
        let (workspace, windows, group) = makeNestedWorkspace()
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout tabbed")
        workspace.syncTabbedGroups()
        let tabs = try XCTUnwrap(workspace.tabbedGroups.first)
        XCTAssertTrue(reorderWorkspaceTab(windows[0], stripId: ObjectIdentifier(tabs), toIndex: 2))
        XCTAssertEqual(tabs.windowIds, [windows[1], windows[2], windows[0]].map(\.windowId))
        XCTAssertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.elementsEqual(windows, by: ===),
            "Only the bar's order changes; Dwindle returns to the same tree")
        _ = try await run("move left")
        XCTAssertEqual(tabs.windowIds, [windows[1], windows[0], windows[2]].map(\.windowId))
        XCTAssertFalse(reorderWorkspaceTab(windows[0], stripId: ObjectIdentifier(group), toIndex: 0), "Another strip's id is not this bar")
    }

    /// Two tab groups side by side: Finder-like left window alone, the nested group's tabs on the right.
    private func makeTwoGroups() async throws -> (Workspace, [TestWindow], TabbedGroup, TabbedGroup) {
        let (workspace, windows, _) = makeNestedWorkspace()
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout tabbed")
        workspace.syncTabbedGroups()
        let first = try XCTUnwrap(workspace.tabbedGroups.first)
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(windows[1].windowId, beside: first, on: .right))
        XCTAssertTrue(workspace.moveTabbedTab(windows[2].windowId, into: try XCTUnwrap(workspace.tabbedGroup(containing: windows[1].windowId))))
        _ = windows[0].focusWindow()
        try await workspace.layoutWorkspace()
        return (workspace, windows, first, try XCTUnwrap(workspace.tabbedGroup(containing: windows[1].windowId)))
    }

    func testGroupsShowSideBySideEachWithItsOwnTab() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        XCTAssertEqual(workspace.tabbedGroups.count, 2)
        XCTAssertEqual(left.windowIds, [windows[0].windowId])
        XCTAssertEqual(right.windowIds, [windows[1], windows[2]].map(\.windowId))
        let a = try XCTUnwrap(windows[0].lastAppliedLayoutPhysicalRect)
        let b = try XCTUnwrap(right.activeWindow?.lastAppliedLayoutPhysicalRect)
        XCTAssertLessThan(a.topLeftX, b.topLeftX, "The new group opened on the right")
        XCTAssertEqual(a.topLeftY, b.topLeftY, "Both sit under their own bars")
        XCTAssertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.elementsEqual(windows, by: ===), "The tree is untouched")
    }

    func testFocusMovesBetweenGroupsThenThroughTabs() async throws {
        let (_, windows, _, right) = try await makeTwoGroups()
        _ = try await run("focus right")
        XCTAssertTrue(focus.windowOrNil === right.activeWindow, "Right goes to the group on the right")
        _ = right.activeWindow?.focusWindow()
        _ = try await run("focus left")
        XCTAssertTrue(focus.windowOrNil === windows[0], "Left goes back to the other group")
        _ = windows[1].focusWindow()
        _ = try await run("focus tab-next")
        XCTAssertTrue(focus.windowOrNil === windows[2], "tab-next stays in the focused group")
    }

    func testMovePastAGroupsEdgeSendsTheTabToTheNextGroup() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        _ = windows[0].focusWindow()
        _ = try await run("move right")
        XCTAssertEqual(right.windowIds.last, windows[0].windowId, "The tab joined the group on the right")
        XCTAssertEqual(workspace.tabbedGroups.count, 1, "Its empty group closed")
        XCTAssertFalse(workspace.tabbedGroups.contains { $0 === left })
    }

    func testDroppingATabOnAnEdgeOrInTheMiddle() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        XCTAssertEqual(applyTabbedGroupDragIntent(.stackSplit(targetWindowId: windows[0].windowId, position: .below),
            sourceWindow: windows[2]), true)
        XCTAssertEqual(workspace.tabbedGroups.count, 3, "A drop on the bottom edge opened a new group below")
        XCTAssertEqual(workspace.tabbedGroup(containing: windows[2].windowId)?.windowIds, [windows[2].windowId])
        XCTAssertEqual(applyTabbedGroupDragIntent(.tabStack(targetWindowId: windows[0].windowId), sourceWindow: windows[2]), true)
        XCTAssertTrue(workspace.tabbedGroup(containing: windows[2].windowId) === left, "A drop in the middle joins that group")
        XCTAssertEqual(left.activeWindowId, windows[2].windowId)
        XCTAssertEqual(right.windowIds, [windows[1].windowId])
        let other = TestWindow.new(id: 29900, parent: Workspace.get(byName: "elsewhere").rootTilingContainer)
        XCTAssertEqual(applyTabbedGroupDragIntent(.tabStack(targetWindowId: windows[1].windowId), sourceWindow: other), true)
        XCTAssertTrue(other.nodeWorkspace === workspace, "A window from another workspace comes over")
        XCTAssertTrue(workspace.tabbedGroup(containing: other.windowId) === right, "into the group it was dropped on")
        XCTAssertEqual(right.activeWindowId, other.windowId)
    }

    func testNewWindowsJoinTheGroupBeingWorkedIn() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        _ = windows[1].focusWindow()
        workspace.syncTabbedGroups()
        let opened = TestWindow.new(id: 29400, parent: workspace.rootTilingContainer)
        _ = opened.focusWindow()
        workspace.syncTabbedGroups()
        XCTAssertTrue(workspace.tabbedGroup(containing: opened.windowId) === right)
        XCTAssertEqual(right.activeWindowId, opened.windowId)
        opened.unbindFromParent()
        windows[1].unbindFromParent()
        windows[2].unbindFromParent()
        workspace.syncTabbedGroups()
        XCTAssertEqual(workspace.tabbedGroups.count, 1, "A group whose windows all closed disappears")
    }

    func testAWindowThatLeavesTheWorkspaceLeavesItsGroup() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        windows[2].unbindFromParent()
        windows[2].bind(to: Workspace.get(byName: "elsewhere").rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        workspace.syncTabbedGroups()
        XCTAssertEqual(right.windowIds, [windows[1].windowId], "A window moved elsewhere is no longer a tab here")
        _ = windows[1].focusWindow()
        _ = try await run("focus --boundaries-action wrap-around-the-workspace tab-next")
        XCTAssertTrue(focus.windowOrNil === windows[1], "tab-next never reaches a window that left")
    }

    func testResizingChangesTheGroupsNotTheTree() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        let before = try XCTUnwrap(left.lastFrame).width
        let ratiosBefore = workspace.rootTilingContainer.allLeafWindowsRecursive.map { $0.parent?.getWeight(.h) }
        _ = windows[0].focusWindow()
        let result = try await run("resize width +100")
        XCTAssertEqual(result.exitCode, 0)
        try await workspace.layoutWorkspace()
        XCTAssertEqual(try XCTUnwrap(left.lastFrame).width, before + 100, accuracy: 2, "The left group grew by 100 points")
        XCTAssertLessThan(try XCTUnwrap(right.lastFrame).width, before, "at the right group's expense")
        XCTAssertEqual(workspace.rootTilingContainer.allLeafWindowsRecursive.map { $0.parent?.getWeight(.h) }, ratiosBefore,
            "The tree kept for other arrangements is untouched")
        let shown = try XCTUnwrap(windows[0].lastAppliedLayoutPhysicalRect)
        applyResizeWithMouse(windows[0], rect: Rect(topLeftX: shown.topLeftX, topLeftY: shown.topLeftY, width: shown.width - 60, height: shown.height))
        try await workspace.layoutWorkspace()
        XCTAssertEqual(try XCTUnwrap(left.lastFrame).width, before + 40, accuracy: 2, "Dragging the right edge in shrinks it")
    }

    func testTheResizePreviewShowsTheProposedGroups() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        _ = windows[0].focusWindow()
        try await workspace.layoutWorkspace()
        let leftBefore = try XCTUnwrap(left.lastFrame), rightBefore = try XCTUnwrap(right.lastFrame)
        let shown = try XCTUnwrap(windows[0].lastAppliedLayoutPhysicalRect)
        let (_, layout) = try XCTUnwrap(proposedTabbedMouseResize(windows[0], rect: Rect(topLeftX: shown.topLeftX,
            topLeftY: shown.topLeftY, width: shown.width + 50, height: shown.height)))
        let items = tabbedResizePreviewItems(in: workspace, layout: layout, excluding: windows[0])
        XCTAssertEqual(items.map(\.id), [try XCTUnwrap(right.activeWindow).windowId], "Only the other group's shown tab is drawn")
        XCTAssertEqual(try XCTUnwrap(items.first).frame.width, rightBefore.width - 50, accuracy: 2, "at its proposed size")
        XCTAssertEqual(try XCTUnwrap(left.lastFrame), leftBefore, "Previewing changes nothing")
    }

    func testDroppingOnAnotherGroupIgnoresTheTreesTabGroup() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(windows[2].windowId, beside: right, on: .right))
        try await workspace.layoutWorkspace()
        XCTAssertTrue(windows[1].parent === windows[2].parent, "Both still share one tab group in the tree")
        let area = try XCTUnwrap(right.lastFrame)
        let destination = try XCTUnwrap(currentWindowSurfaceDestination(sourceWindow: windows[2],
            mouseLocation: CGPoint(x: area.center.x, y: area.center.y), subject: .window, detachOrigin: .tabStrip))
        XCTAssertEqual(destination.kind, .tabStack(targetWindowId: windows[1].windowId), "The middle moves the tab into that group")
        XCTAssertEqual(destination.dropIntentOverlay?.targetFrame, area, "The whole group, its bar included, is the target")
        let edge = try XCTUnwrap(currentWindowSurfaceDestination(sourceWindow: windows[2],
            mouseLocation: CGPoint(x: area.minX + 4, y: area.center.y), subject: .window, detachOrigin: .tabStrip))
        XCTAssertEqual(edge.kind, .stackSplit(targetWindowId: windows[1].windowId, position: .left))
        XCTAssertEqual(applyTabbedGroupDragIntent(destination.kind, sourceWindow: windows[2]), true)
        XCTAssertEqual(right.windowIds, [windows[1], windows[2]].map(\.windowId))
    }

    func testResizingASingleGroupIsANoOp() async throws {
        let (workspace, windows, _) = makeNestedWorkspace()
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout tabbed")
        let result = try await run("resize width +100")
        XCTAssertEqual(result.exitCode, 0, "Nothing to resize does not fail a command chain")
        XCTAssertEqual(workspace.tabbedGroups.count, 1)
    }

    func testARestoredGroupKeepsItsSavedTab() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        right.activeWindowId = windows[1].windowId
        windows[2].markAsMostRecentChild()
        workspace.syncTabbedGroups()
        XCTAssertEqual(right.activeWindowId, windows[1].windowId, "Rebinding in order is not a focus change")
        _ = windows[2].focusWindow()
        workspace.syncTabbedGroups()
        XCTAssertEqual(right.activeWindowId, windows[2].windowId, "Focusing a tab shows it")
    }

    func testSmartResizeFollowsTheGroupsSplit() async throws {
        let (workspace, windows, _) = makeNestedWorkspace()
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout tabbed")
        let only = try XCTUnwrap(workspace.tabbedGroups.first)
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(windows[1].windowId, beside: only, on: .down))
        _ = windows[0].focusWindow()
        try await workspace.layoutWorkspace()
        let top = try XCTUnwrap(only.lastFrame).height
        let result = try await run("resize smart +80")
        XCTAssertEqual(result.exitCode, 0, "Rows resize along their height")
        try await workspace.layoutWorkspace()
        XCTAssertEqual(try XCTUnwrap(only.lastFrame).height, top + 80, accuracy: 2)
    }

    func testRestoringATabbedWorkspaceKeepsSavedTabs() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        right.activeWindowId = windows[1].windowId
        windows[2].markAsMostRecentChild()
        workspace.transitionArrangement(to: .tabbed)
        XCTAssertEqual(right.activeWindowId, windows[1].windowId, "Restoring an already Tabbed workspace is not a switch")
    }

    func testDraggingAnOuterEdgeMovesTheOuterDivider() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(windows[2].windowId, beside: right, on: .right))
        try await workspace.layoutWorkspace()
        let leftWidth = try XCTUnwrap(left.lastFrame).width
        let shown = try XCTUnwrap(windows[1].lastAppliedLayoutPhysicalRect)
        applyResizeWithMouse(windows[1], rect: Rect(topLeftX: shown.topLeftX - 50, topLeftY: shown.topLeftY, width: shown.width + 50, height: shown.height))
        try await workspace.layoutWorkspace()
        XCTAssertEqual(try XCTUnwrap(left.lastFrame).width, leftWidth - 50, accuracy: 2, "Dragging the left edge moves the divider on the left")
    }

    func testResizingNextToAMinimumSizeMovesTheRequestedPoints() async throws {
        let (workspace, windows, left, _) = try await makeTwoGroups()
        windows[0].testMinimumSize = CGSize(width: 1000, height: 100)
        try await workspace.layoutWorkspace()
        let before = try XCTUnwrap(left.lastFrame).width
        XCTAssertTrue(workspace.resizeTabbedGroup(of: windows[0], along: .h, by: 100))
        try await workspace.layoutWorkspace()
        XCTAssertEqual(try XCTUnwrap(left.lastFrame).width, before + 100, accuracy: 2)
    }

    func testResizingLeavesUninvolvedGroupsAlone() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(windows[2].windowId, beside: right, on: .right))
        try await workspace.layoutWorkspace()
        let third = try XCTUnwrap(workspace.tabbedGroup(containing: windows[2].windowId))
        let thirdWidth = try XCTUnwrap(third.lastFrame).width
        _ = windows[0].focusWindow()
        XCTAssertTrue(workspace.resizeTabbedGroup(of: windows[0], along: .h, by: 60))
        try await workspace.layoutWorkspace()
        XCTAssertEqual(try XCTUnwrap(third.lastFrame).width, thirdWidth, accuracy: 1, "Only the two groups at the divider change")
        XCTAssertTrue(workspace.tabbedGroups.contains { $0 === left })
    }

    func testResizingWorksWhileAnotherGroupIsHidden() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(windows[2].windowId, beside: right, on: .right))
        try await workspace.layoutWorkspace()
        right.lastFrame = nil
        let before = try XCTUnwrap(left.lastFrame).width
        XCTAssertTrue(workspace.resizeTabbedGroup(of: windows[0], along: .h, by: 50), "The hidden middle group does not block resizing")
        XCTAssertGreaterThan(before, 0)
    }

    func testResizingStopsAtTheNeighboursMinimumSize() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        try await workspace.layoutWorkspace()
        let rightWidth = try XCTUnwrap(right.lastFrame).width
        try XCTUnwrap(right.activeWindow as? TestWindow).testMinimumSize = CGSize(width: rightWidth - 30, height: 100)
        let before = try XCTUnwrap(left.lastFrame).width
        XCTAssertTrue(workspace.resizeTabbedGroup(of: windows[0], along: .h, by: 300))
        try await workspace.layoutWorkspace()
        XCTAssertEqual(try XCTUnwrap(left.lastFrame).width, before + 30, accuracy: 2, "Only the room the neighbour can spare moves")
    }

    func testMovingTheFocusedTabMovesWhereNewWindowsGo() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        _ = windows[0].focusWindow()
        _ = try await run("move right")
        let opened = TestWindow.new(id: 29700, parent: workspace.rootTilingContainer)
        workspace.syncTabbedGroups()
        XCTAssertTrue(workspace.tabbedGroup(containing: opened.windowId) === right, "New windows follow the moved tab")
    }

    func testAMissingChosenTabKeepsItsChoice() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        right.activeWindowId = windows[2].windowId
        windows[2].unbindFromParent()
        right.windowIds.append(windows[2].windowId)
        XCTAssertTrue(right.activeWindow === windows[1], "While the chosen window is missing another tab shows")
        XCTAssertEqual(right.activeWindowId, windows[2].windowId, "but the choice is kept")
        windows[2].bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        XCTAssertTrue(right.activeWindow === windows[2], "and it shows again when its window returns")
    }

    func testATabInNativeFullscreenKeepsItsPlace() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        windows[2].unbindFromParent()
        windows[2].bind(to: workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        workspace.syncTabbedGroups()
        XCTAssertEqual(right.windowIds, [windows[1], windows[2]].map(\.windowId), "Native fullscreen keeps the tab's place")
        XCTAssertEqual(right.shownWindowIds, [windows[1].windowId], "though its bar leaves it out meanwhile")
    }

    func testNewWindowsFindTheFocusedGroupAfterARestore() async throws {
        let (workspace, windows, _, _) = try await makeTwoGroups()
        _ = windows[2].focusWindow()
        let frozen = try XCTUnwrap(workspace.tabbedLayout.map(FrozenTabbedLayout.init))
        workspace.tabbedLayout = frozen.restored(Dictionary(uniqueKeysWithValues: windows.map { ($0.windowId, $0 as Window) }))
        let opened = TestWindow.new(id: 29800, parent: workspace.rootTilingContainer)
        workspace.syncTabbedGroups()
        XCTAssertTrue(workspace.tabbedGroup(containing: opened.windowId) === workspace.tabbedGroup(containing: windows[2].windowId),
            "New windows still join the group being worked in")
    }

    func testGroupsSurviveARestartWithNewWindowIds() async throws {
        let (workspace, windows, _, _) = try await makeTwoGroups()
        let frozen = try XCTUnwrap(workspace.tabbedLayout.map(FrozenTabbedLayout.init))
        let decoded = try JSONDecoder().decode(FrozenTabbedLayout.self, from: JSONEncoder().encode(frozen))
        let replacements = Dictionary(uniqueKeysWithValues: windows.enumerated().map { index, window in
            (window.windowId, TestWindow.new(id: UInt32(29500 + index), parent: workspace.rootTilingContainer) as Window)
        })
        let restored = try XCTUnwrap(decoded.restored(replacements))
        XCTAssertEqual(restored.groups.map(\.windowIds), [[29500], [29501, 29502]], "Saved IDs map to the restored windows")
        let partial = try XCTUnwrap(decoded.restored([windows[0].windowId: replacements[windows[0].windowId]!]))
        XCTAssertEqual(partial.groups.count, 2, "A group whose windows are not back yet keeps its place")
        XCTAssertEqual(partial.groups.last?.windowIds, [windows[1], windows[2]].map(\.windowId))
    }

    func testGroupsMakeRoomForTheirWindowsMinimumSize() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        windows[0].testMinimumSize = CGSize(width: 1200, height: 100)
        let rect = workspaceTilingRect(workspace)
        let frames = try XCTUnwrap(workspace.tabbedLayout).frames(in: rect, gap: .zero)
        let leftFrame = try XCTUnwrap(frames.first { $0.0 === left }?.1)
        XCTAssertGreaterThanOrEqual(leftFrame.width, min(1200, rect.width), "The left group widens for its window")
        XCTAssertTrue(frames.contains { $0.0 === right })
    }

    func testAFloatingWindowDroppedOnAnEdgeOpensAGroupThere() async throws {
        let (workspace, windows, left, _) = try await makeTwoGroups()
        let floating = TestWindow.new(id: 29600, parent: workspace)
        XCTAssertEqual(applyTabbedGroupDragIntent(.stackSplit(targetWindowId: windows[0].windowId, position: .below),
            sourceWindow: floating), true)
        XCTAssertTrue(floating.parent is TilingContainer, "The window is tiled now")
        let group = try XCTUnwrap(workspace.tabbedGroup(containing: floating.windowId))
        XCTAssertFalse(group === left)
        XCTAssertEqual(group.windowIds, [floating.windowId], "It opened its own group, not the focused one")
        XCTAssertEqual(workspace.tabbedGroups.count, 3)
    }

    func testAWindowDroppedIntoTheFocusedGroupShows() async throws {
        let (workspace, windows, left, _) = try await makeTwoGroups()
        let floating = TestWindow.new(id: 29650, parent: workspace)
        XCTAssertEqual(applyTabbedGroupDragIntent(.tabStack(targetWindowId: windows[0].windowId), sourceWindow: floating), true)
        XCTAssertTrue(workspace.tabbedGroup(containing: floating.windowId) === left)
        XCTAssertEqual(left.activeWindowId, floating.windowId, "The dropped window is the tab shown")
    }

    func testTheShownTabSplitsBesideItsOwnGroup() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        _ = windows[1].focusWindow()
        try await workspace.layoutWorkspace()
        let area = try XCTUnwrap(right.lastFrame)
        XCTAssertNil(currentWindowSurfaceDestination(sourceWindow: windows[1], mouseLocation: CGPoint(x: area.center.x, y: area.center.y),
            subject: .window, detachOrigin: .tabStrip), "The middle of its own group changes nothing")
        let edge = try XCTUnwrap(currentWindowSurfaceDestination(sourceWindow: windows[1],
            mouseLocation: CGPoint(x: area.center.x, y: area.maxY - 4), subject: .window, detachOrigin: .tabStrip))
        XCTAssertEqual(edge.kind, .stackSplit(targetWindowId: windows[1].windowId, position: .below))
        XCTAssertEqual(applyTabbedGroupDragIntent(edge.kind, sourceWindow: windows[1]), true)
        XCTAssertEqual(right.windowIds, [windows[2].windowId])
        XCTAssertEqual(workspace.tabbedGroup(containing: windows[1].windowId)?.windowIds, [windows[1].windowId])
        XCTAssertEqual(workspace.tabbedGroups.count, 3)
    }

    func testMergingGroups() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        XCTAssertTrue(workspace.mergeTabbedGroup(right, into: left))
        XCTAssertEqual(left.windowIds, windows.map(\.windowId), "Its tabs follow the group's own")
        XCTAssertEqual(left.activeWindowId, right.activeWindowId, "showing the tab the merged group showed")
        XCTAssertEqual(workspace.tabbedGroups.count, 1)
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(windows[1].windowId, beside: left, on: .right))
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(windows[2].windowId, beside: left, on: .down))
        XCTAssertEqual(workspace.tabbedGroups.count, 3)
        XCTAssertTrue(workspace.mergeAllTabbedGroups(into: left))
        XCTAssertEqual(workspace.tabbedGroups.count, 1)
        XCTAssertEqual(Set(left.windowIds), Set(windows.map(\.windowId)))
        XCTAssertFalse(workspace.mergeAllTabbedGroups(into: left), "One group has nothing to merge")
    }

    func testTheHandleCarriesTheWholeGroup() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        XCTAssertEqual(applyTabbedGroupDragIntent(.stackSplit(targetWindowId: windows[0].windowId, position: .left),
            sourceWindow: windows[1], subject: .group), true)
        XCTAssertEqual(workspace.tabbedGroups.map(\.windowIds), [right.windowIds, left.windowIds], "The whole group moved to the left")
        XCTAssertEqual(right.windowIds.count, 2)
        let area = try XCTUnwrap(left.lastFrame)
        let merge = try XCTUnwrap(currentWindowSurfaceDestination(sourceWindow: windows[1],
            mouseLocation: CGPoint(x: area.center.x, y: area.center.y), subject: .group, detachOrigin: .tabStrip))
        XCTAssertEqual(merge.title, "Merge Tab Groups")
        XCTAssertEqual(applyTabbedGroupDragIntent(merge.kind, sourceWindow: windows[1], subject: .group), true)
        XCTAssertEqual(workspace.tabbedGroups.count, 1)
        XCTAssertEqual(left.windowIds, [windows[0], windows[1], windows[2]].map(\.windowId))
    }

    func testAHandleCarriesItsGroupToAnotherTabbedWorkspace() async throws {
        let (workspace, windows, left, _) = try await makeTwoGroups()
        let other = Workspace.get(byName: "elsewhere")
        other.arrangement = .tabbed
        let resident = TestWindow.new(id: 29950, parent: other.rootTilingContainer)
        other.syncTabbedGroups()
        XCTAssertEqual(applyTabbedGroupDragIntent(.tabStack(targetWindowId: resident.windowId), sourceWindow: windows[2], subject: .group), true)
        let joined = try XCTUnwrap(other.tabbedGroup(containing: resident.windowId))
        XCTAssertEqual(joined.activeWindowId, windows[2].windowId, "Dragged by its second tab, the group keeps its order")
        XCTAssertEqual(joined.windowIds, [resident, windows[1], windows[2]].map(\.windowId), "Both tabs of the group came over")
        XCTAssertTrue(windows[0].nodeWorkspace === workspace, "The rest of the tree stayed")
        workspace.syncTabbedGroups()
        XCTAssertEqual(workspace.tabbedGroups.map(\.windowIds), [left.windowIds])
    }

    func testAGroupMovedToAnotherWorkspaceKeepsItsFullscreenTab() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        windows[2].bind(to: workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        windows[2].layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name)
        workspace.syncTabbedGroups()
        XCTAssertEqual(right.windowIds, [windows[1], windows[2]].map(\.windowId))
        let other = Workspace.get(byName: "elsewhere")
        other.arrangement = .tabbed
        let resident = TestWindow.new(id: 29960, parent: other.rootTilingContainer)
        other.syncTabbedGroups()
        XCTAssertEqual(applyTabbedGroupDragIntent(.tabStack(targetWindowId: resident.windowId), sourceWindow: windows[1], subject: .group), true)
        XCTAssertTrue(windows[2].nodeWorkspace === other, "The fullscreen window belongs to the new workspace")
        XCTAssertTrue(windows[2].parent is MacosFullscreenWindowsContainer, "and stays fullscreen")
        guard case .macos(_, let returnsTo) = windows[2].layoutReason else { return XCTFail("Still waiting on macOS") }
        XCTAssertEqual(returnsTo, other.name, "Leaving fullscreen, it returns to its moved group")
        other.syncTabbedGroups()
        XCTAssertEqual(other.tabbedGroup(containing: resident.windowId)?.windowIds, [resident, windows[1], windows[2]].map(\.windowId))
        workspace.syncTabbedGroups()
        XCTAssertNil(workspace.tabbedGroup(containing: windows[2].windowId))
    }

    func testAGroupMovedToAnotherWorkspaceComesWhole() async throws {
        let (workspace, windows, left, _) = try await makeTwoGroups()
        let other = Workspace.get(byName: "elsewhere")
        let carried = try XCTUnwrap(tabbedGroupCarried(by: windows[2]))
        windows[2].unbindFromParent()
        windows[2].bind(to: other.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        bringTabbedGroupAlong(carried, after: windows[2])
        XCTAssertTrue(windows[1].nodeWorkspace === other, "The group's other tab followed")
        XCTAssertEqual(workspace.tabbedGroups.map(\.windowIds), [left.windowIds], "Only the left group stays behind")
    }

    func testAGroupMovedIntoATabbedWorkspaceKeepsItsOrder() async throws {
        let (_, windows, _, _) = try await makeTwoGroups()
        let other = Workspace.get(byName: "elsewhere")
        other.arrangement = .tabbed
        let resident = TestWindow.new(id: 29970, parent: other.rootTilingContainer)
        other.syncTabbedGroups()
        let carried = try XCTUnwrap(tabbedGroupCarried(by: windows[2]))
        windows[2].unbindFromParent()
        windows[2].bind(to: other.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        bringTabbedGroupAlong(carried, after: windows[2])
        let group = try XCTUnwrap(other.tabbedGroup(containing: windows[2].windowId))
        XCTAssertEqual(group.windowIds, [resident, windows[1], windows[2]].map(\.windowId), "Its tabs arrive in order")
        XCTAssertEqual(group.activeWindowId, windows[2].windowId)
    }

    func testSplitAndJoinWithWorkOnGroups() async throws {
        let (workspace, windows, _) = makeNestedWorkspace()
        _ = windows[1].focusWindow()
        _ = try await run("workspace-layout tabbed")
        let split = try await run("split vertical")
        XCTAssertEqual(split.exitCode, 0)
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.tabbedGroups.count, 2)
        let below = try XCTUnwrap(workspace.tabbedGroup(containing: windows[1].windowId))
        XCTAssertEqual(below.windowIds, [windows[1].windowId], "The tab opened in a row below")
        XCTAssertTrue(focus.windowOrNil === windows[1])
        let joined = try await run("join-with up")
        XCTAssertEqual(joined.exitCode, 0)
        XCTAssertEqual(workspace.tabbedGroups.count, 1, "It joined the group above")
        let nothing = try await run("join-with left")
        XCTAssertEqual(nothing.exitCode, 0, "Nothing on that side is not a failure")
        XCTAssertEqual(workspace.tabbedGroups.count, 1)
        _ = windows[0].focusWindow()
        let explicit = try await run("split --window-id \(windows[2].windowId) horizontal")
        XCTAssertEqual(explicit.exitCode, 0)
        XCTAssertTrue(focus.windowOrNil === windows[0], "Splitting another window leaves focus where it was")
        XCTAssertEqual(workspace.tabbedGroup(containing: windows[2].windowId)?.windowIds, [windows[2].windowId])
    }

    /// Three columns, [0] [1] [2], each window needing `width` points.
    private func makeThreeColumns(width: CGFloat) async throws -> (Workspace, [TestWindow], [TabbedGroup]) {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(windows[2].windowId, beside: right, on: .right))
        for window in windows { window.testMinimumSize = CGSize(width: width, height: 100) }
        _ = windows[0].focusWindow()
        try await workspace.layoutWorkspace()
        return (workspace, windows, workspace.tabbedGroups)
    }

    func testAGroupWithoutRoomFoldsIntoItsNeighboursBar() async throws {
        let rect = workspaceTilingRect(focus.workspace)
        let (workspace, windows, groups) = try await makeThreeColumns(width: (rect.width - 40) / 2)
        XCTAssertEqual(groups.count, 3, "The groups themselves stay")
        XCTAssertTrue(groups[2].foldedInto === groups[1], "The group farthest from the one in use folded into its neighbour")
        XCTAssertNil(groups[2].lastFrame, "It has no area of its own")
        XCTAssertEqual(groups[1].barWindowIds, [windows[1], windows[2]].map(\.windowId), "Its tab shows in that bar")
        let a = try XCTUnwrap(groups[0].lastFrame), b = try XCTUnwrap(groups[1].lastFrame)
        XCTAssertLessThanOrEqual(a.maxX, b.minX + 1, "The two groups shown no longer overlap")
        _ = windows[2].focusWindow()
        try await workspace.layoutWorkspace()
        XCTAssertTrue(groups[1].displayedWindow === windows[2], "Choosing the folded tab shows it in that area")
        XCTAssertNotNil(windows[2].lastAppliedLayoutPhysicalRect)
        XCTAssertNil(windows[1].lastAppliedLayoutPhysicalRect)
        _ = windows[0].focusWindow()
        try await workspace.layoutWorkspace()
        XCTAssertTrue(groups[2].foldedInto === groups[1], "The folds stay as they were")
        let result = try await run("focus --tab-index 2")
        XCTAssertNotEqual(result.exitCode, 0, "Tab indices count the focused bar's own tabs, here one")
        for window in windows { window.testMinimumSize = .zero }
        try await workspace.layoutWorkspace()
        XCTAssertNil(groups[2].foldedInto, "With room again the group returns")
        XCTAssertNotNil(groups[2].lastFrame)
    }

    func testReorderingInAFoldedBarKeepsEachTabInItsGroup() async throws {
        let rect = workspaceTilingRect(focus.workspace)
        let (workspace, windows, groups) = try await makeThreeColumns(width: (rect.width - 40) / 2)
        let extra = TestWindow.new(id: 29980, parent: workspace.rootTilingContainer)
        extra.testMinimumSize = windows[2].testMinimumSize
        workspace.syncTabbedGroups()
        XCTAssertTrue(workspace.moveTabbedTab(extra.windowId, into: groups[2]))
        _ = windows[0].focusWindow()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(groups[1].barWindowIds, [windows[1], windows[2], extra].map(\.windowId))
        XCTAssertTrue(reorderWorkspaceTab(extra, stripId: ObjectIdentifier(groups[1]), toIndex: 1))
        XCTAssertEqual(groups[2].windowIds, [extra, windows[2]].map(\.windowId), "It moved before its own group's tab")
        XCTAssertTrue(reorderWorkspaceTab(extra, stripId: ObjectIdentifier(groups[1]), toIndex: 0))
        XCTAssertEqual(groups[1].windowIds, [windows[1].windowId], "but never into the host's group")
    }

    func testAFoldedGroupDoesNotCountTwiceWhenResizing() async throws {
        let rect = workspaceTilingRect(focus.workspace)
        let (workspace, _, groups) = try await makeThreeColumns(width: (rect.width - 40) / 2)
        XCTAssertTrue(groups[2].foldedInto === groups[1])
        let layout = try XCTUnwrap(workspace.tabbedLayout)
        XCTAssertEqual(layout.minimumExtent(horizontal: true, gap: .zero),
                       try XCTUnwrap(workspace.presentedTabbedLayout).minimumExtent(horizontal: true, gap: .zero), accuracy: 0.5,
                       "The stored layout needs no more room than what is shown")
    }

    func testANewWindowShowsInAFoldedBar() async throws {
        let rect = workspaceTilingRect(focus.workspace)
        let (workspace, windows, groups) = try await makeThreeColumns(width: (rect.width - 40) / 2)
        _ = windows[2].focusWindow()
        try await workspace.layoutWorkspace()
        XCTAssertTrue(groups[1].displayedWindow === windows[2])
        workspace.lastTabbedGroup = groups[1]
        let newcomer = TestWindow.new(id: 29990, parent: workspace.rootTilingContainer)
        _ = newcomer.focusWindow()
        try await workspace.layoutWorkspace()
        XCTAssertTrue(workspace.tabbedGroup(containing: newcomer.windowId)?.barGroup === groups[1])
        XCTAssertTrue(groups[1].displayedWindow === newcomer, "The window that opened and took focus shows")
    }

    func testAFoldedTabInUseStaysShownWhenItsHostCloses() async throws {
        let rect = workspaceTilingRect(focus.workspace)
        let (workspace, windows, groups) = try await makeThreeColumns(width: (rect.width - 40) / 2)
        let extra = TestWindow.new(id: 29985, parent: workspace.rootTilingContainer)
        extra.testMinimumSize = windows[0].testMinimumSize
        workspace.syncTabbedGroups()
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(extra.windowId, beside: groups[0], on: .left))
        _ = windows[0].focusWindow()
        try await workspace.layoutWorkspace()
        let folded = try XCTUnwrap(workspace.tabbedGroups.first { $0.foldedInto != nil })
        let shownWindow = try XCTUnwrap(folded.activeWindow)
        _ = shownWindow.focusWindow()
        try await workspace.layoutWorkspace()
        let host = try XCTUnwrap(folded.foldedInto)
        for id in host.windowIds { Window.get(byId: id)?.unbindFromParent() }
        workspace.syncTabbedGroups()
        try await workspace.layoutWorkspace()
        XCTAssertNotNil(shownWindow.lastAppliedLayoutPhysicalRect, "The tab in use is still shown")
    }

    func testTabNextGoesThroughFoldedTabs() async throws {
        let rect = workspaceTilingRect(focus.workspace)
        let (workspace, windows, groups) = try await makeThreeColumns(width: (rect.width - 40) / 2)
        _ = windows[1].focusWindow()
        try await workspace.layoutWorkspace()
        XCTAssertTrue(groups[1].foldedGroups.isEmpty == false || groups[0].foldedGroups.isEmpty == false)
        let bar = try XCTUnwrap(workspace.tabbedGroup(containing: windows[1].windowId)?.barGroup.barWindowIds)
        XCTAssertGreaterThan(bar.count, 1)
        let result = try await run("focus --boundaries-action wrap-around-the-workspace tab-next")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(focus.windowOrNil?.windowId, bar[(bar.firstIndex(of: windows[1].windowId)! + 1) % bar.count])
    }

    func testAGroupIsNeverResizedBelowItsWidestWindow() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        windows[1].testMinimumSize = CGSize(width: 300, height: 100)
        windows[2].testMinimumSize = CGSize(width: 700, height: 100)
        _ = windows[1].focusWindow()
        try await workspace.layoutWorkspace()
        XCTAssertTrue(right.displayedWindow === windows[1])
        _ = windows[0].focusWindow()
        let result = try await run("resize width +5000")
        XCTAssertEqual(result.exitCode, 0)
        try await workspace.layoutWorkspace()
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(right.lastFrame).width, 700 - 1,
            "The tab not shown still keeps its group wide enough for its window")
        _ = left
    }

    func testATabDroppedOnAnotherBarGoesWhereThePointerIs() async throws {
        let (workspace, windows, left, right) = try await makeTwoGroups()
        let bar = tabbedBarTabsRect(area: try XCTUnwrap(right.lastFrame))
        let first = CGPoint(x: bar.minX + 6, y: bar.center.y)
        let destination = try XCTUnwrap(currentWindowSurfaceDestination(sourceWindow: windows[0], mouseLocation: first,
                                                                         subject: .window, detachOrigin: .tabStrip))
        XCTAssertEqual(destination.kind, .insertTab(targetWindowId: try XCTUnwrap(right.displayedWindow).windowId, index: 0))
        XCTAssertEqual(applyTabbedGroupDragIntent(destination.kind, sourceWindow: windows[0]), true)
        XCTAssertEqual(right.windowIds, [windows[0], windows[1], windows[2]].map(\.windowId), "It went before the first tab")
        XCTAssertFalse(workspace.tabbedGroups.contains { $0 === left }, "Its empty group closed")
    }

    func testATabBackOverItsOwnBarMovesAlongIt() async throws {
        let (workspace, windows, _, right) = try await makeTwoGroups()
        _ = windows[1].focusWindow()
        try await workspace.layoutWorkspace()
        let bar = tabbedBarTabsRect(area: try XCTUnwrap(right.lastFrame))
        let end = CGPoint(x: bar.maxX - 80, y: bar.center.y)
        let destination = try XCTUnwrap(currentWindowSurfaceDestination(sourceWindow: windows[1], mouseLocation: end,
                                                                         subject: .window, detachOrigin: .tabStrip))
        XCTAssertEqual(destination.kind, .reorderTab(windowId: windows[1].windowId, targetIndex: 1))
        XCTAssertTrue(workspace.insertTabbedTab(windows[1].windowId, intoBarOf: right, at: 1))
        XCTAssertEqual(right.windowIds, [windows[2], windows[1]].map(\.windowId))
    }

    func testDropsOnAScrolledBarFollowItsTabs() async throws {
        let (_, windows, _, right) = try await makeTwoGroups()
        let area = try XCTUnwrap(right.lastFrame)
        let tabs = tabbedBarTabsRect(area: area)
        let pointer = CGPoint(x: tabs.minX + 6, y: tabs.center.y)
        right.barScrollOffset = -120
        XCTAssertEqual(tabbedBarTabsRect(area: area, host: right).minX, tabs.minX - 120)
        let destination = try XCTUnwrap(currentWindowSurfaceDestination(sourceWindow: windows[0], mouseLocation: pointer,
                                                                         subject: .window, detachOrigin: .tabStrip))
        guard case .insertTab(_, let index) = destination.kind else { return XCTFail("Not a bar drop") }
        XCTAssertGreaterThan(index, 0, "With the first tab scrolled away, the pointer is past it")
    }

    func testInsertingIntoAFoldedBarJoinsTheGroupOfTheTabItLandsBefore() async throws {
        let rect = workspaceTilingRect(focus.workspace)
        let (workspace, windows, groups) = try await makeThreeColumns(width: (rect.width - 40) / 2)
        XCTAssertEqual(groups[1].barWindowIds, [windows[1], windows[2]].map(\.windowId))
        XCTAssertTrue(workspace.insertTabbedTab(windows[0].windowId, intoBarOf: groups[1], at: 1))
        XCTAssertEqual(groups[2].windowIds, [windows[0], windows[2]].map(\.windowId))
        XCTAssertEqual(groups[2].activeWindowId, windows[0].windowId)
        XCTAssertEqual(groups[1].barWindowIds, [windows[1], windows[0], windows[2]].map(\.windowId))
        XCTAssertTrue(workspace.insertTabbedTab(windows[1].windowId, intoBarOf: groups[1], at: 0))
        XCTAssertEqual(groups[1].windowIds, [windows[1].windowId], "Put back where it was, a tab keeps its own group")
    }

    func testJoiningAGroupWorksWithWindowTabsOff() {
        let previous = config.windowTabs.enabled
        config.windowTabs.enabled = false
        defer { config.windowTabs.enabled = previous }
        let workspace = focus.workspace
        workspace.arrangement = .tabbed
        let window = TestWindow.new(id: 29700, parent: workspace.rootTilingContainer)
        XCTAssertTrue(isWindowDragIntentKindEnabled(.tabStack(targetWindowId: window.windowId)))
        workspace.arrangement = .dwindle
        XCTAssertFalse(isWindowDragIntentKindEnabled(.tabStack(targetWindowId: window.windowId)))
    }

    func testSideBySideTabsFromBuild322BecomeColumns() throws {
        let (workspace, windows, _) = makeNestedWorkspace()
        let split = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .h, .tiles, index: INDEX_BIND_LAST)
        windows[0].unbindFromParent()
        windows[0].bind(to: split, adaptiveWeight: WEIGHT_AUTO, index: 0)
        windows[2].unbindFromParent()
        windows[2].bind(to: split, adaptiveWeight: WEIGHT_AUTO, index: 1)
        var frozen = FrozenContainer(workspace.rootTilingContainer)
        func mark(_ container: inout FrozenContainer) {
            for index in container.children.indices {
                guard case .container(var child) = container.children[index] else { continue }
                if child.children.count == 2, case .window(let first) = child.children[0], first.id == windows[0].windowId {
                    child.isTabbedSplit = true
                }
                mark(&child)
                container.children[index] = .container(child)
            }
        }
        mark(&frozen)
        let byId = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowId, $0 as Window) })
        let layout = try XCTUnwrap(migratedTabbedLayout(from: frozen, byId, allWindows: windows.map(\.windowId)))
        XCTAssertEqual(layout.groups.map(\.windowIds), [[windows[1].windowId], [windows[0].windowId], [windows[2].windowId]],
            "The side-by-side pair opens as two columns beside the rest")
    }

    func testConfigSelectsTabbedWhileTabGroupKeepsItsRootMeaning() {
        let parsed = parseConfig("""
        [workspace.'1']
        layout = 'tabbed'
        [workspace.'2']
        layout = 'tab-group'
        """)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.workspaceLayouts["1"]?.defaults.layout, .tabbed)
        XCTAssertEqual(parsed.config.workspaceLayouts["2"]?.defaults.rootLayout, .tabGroup)
    }

}
