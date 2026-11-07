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
        let rect = workspaceTilingRect(workspace)
        let content = workspaceTabbedContentRect(rect)
        let windowFrame = CGRect(x: content.topLeftX, y: content.topLeftY, width: content.width, height: content.height)
        let target = try XCTUnwrap(windowBorderTarget(for: windows[0], nativeFrame: windowFrame))
        XCTAssertEqual(target.frame.minY, rect.topLeftY, "The border starts at the top of the tab bar")
        XCTAssertEqual(target.frame.maxY, windowFrame.maxY)
        XCTAssertEqual(target.frame.width, windowFrame.width)
        windows[0].isFullscreen = true
        XCTAssertEqual(windowBorderTarget(for: windows[0], nativeFrame: windowFrame)?.frame, windowFrame,
            "In fullscreen there is no bar to enclose")
    }

    func testTabCommandsUseTheWorkspaceTabs() async throws {
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

    func testReorderingTabsKeepsTheTreeShape() async throws {
        let (workspace, windows, group) = makeNestedWorkspace()
        _ = windows[0].focusWindow()
        _ = try await run("workspace-layout tabbed")
        XCTAssertTrue(reorderWorkspaceTab(windows[0], stripId: ObjectIdentifier(workspace), toIndex: 2))
        XCTAssertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.elementsEqual([windows[1], windows[2], windows[0]], by: ===))
        XCTAssertEqual(group.children.count, 2, "Slots stay where they were; windows move between them")
        XCTAssertEqual(group.layout, .tabGroup)
        _ = try await run("move left")
        XCTAssertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.elementsEqual([windows[1], windows[0], windows[2]], by: ===),
            "move left moves the focused tab one place along the bar")
        XCTAssertFalse(reorderWorkspaceTab(windows[0], stripId: ObjectIdentifier(group), toIndex: 0), "Another strip's id is not this bar")
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
