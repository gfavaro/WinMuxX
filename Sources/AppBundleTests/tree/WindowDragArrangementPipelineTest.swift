@testable import AppBundle
import AppKit
import Common
import CoreGraphics
import XCTest

@MainActor extension WindowTabsTest {
    private func run(_ text: String) async throws -> CmdResult {
        try await XCTUnwrap(parseCommand(text).cmdOrNil).run(.defaultEnv, .emptyStdin)
    }

    /// A drop on another window's middle swaps the two, found and shown by the tree arrangement
    /// and applied through the whole pipeline.
    func testDwindleSwapRunsThroughThePipeline() throws {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        defer { clearPendingWindowDragIntent() }

        let workspace = focus.workspace
        XCTAssertTrue(workspace.focusWorkspace())
        let root = workspace.rootTilingContainer
        let first = TestWindow.new(id: 9400, parent: root)
        let second = TestWindow.new(id: 9401, parent: root)
        first.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        second.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 220, topLeftY: 0, width: 200, height: 220)
        let mouseLocation = second.swapDropZoneRect.orDie().center
        MousePointerTracker.shared.note(point: mouseLocation)

        XCTAssertTrue(updatePendingWindowDragIntent(sourceWindow: first, mouseLocation: mouseLocation))
        XCTAssertEqual(debugPendingWindowDragIntentSummary()?.kind, .swap(targetWindowId: second.windowId))
        XCTAssertTrue(applyPendingWindowDragIntentIfPossible())

        XCTAssertEqual(root.layoutDescription, .h_tiles([.window(9401), .window(9400)]))
        XCTAssertTrue(focus.windowOrNil === first)
    }

    /// In the Master arrangement an edge drop still splits through the tree: the dragged window
    /// moves to the side it was dropped on.
    func testMasterStackSplitRunsThroughThePipeline() async throws {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        defer { clearPendingWindowDragIntent() }

        let workspace = focus.workspace
        let result = try await run("workspace-layout master")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(workspace.arrangement, .master)
        let root = workspace.rootTilingContainer
        let first = TestWindow.new(id: 9410, parent: root)
        let second = TestWindow.new(id: 9411, parent: root)
        first.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        second.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 220, topLeftY: 0, width: 200, height: 220)
        let mouseLocation = second.stackSplitDropZoneRect(position: .right).orDie().center
        MousePointerTracker.shared.note(point: mouseLocation)

        XCTAssertTrue(updatePendingWindowDragIntent(sourceWindow: first, mouseLocation: mouseLocation))
        XCTAssertEqual(debugPendingWindowDragIntentSummary()?.kind, .stackSplit(targetWindowId: second.windowId, position: .right))
        XCTAssertTrue(applyPendingWindowDragIntentIfPossible())

        XCTAssertEqual(root.layoutDescription, .h_tiles([.window(9411), .window(9410)]))
        XCTAssertTrue(focus.windowOrNil === first)
    }

    /// In the Scrolling arrangement a sideways edge drop opens a column beside the row it was
    /// dropped on, wrapping the target in an h-split of its own.
    func testScrollingStackSplitRunsThroughThePipeline() async throws {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        defer { clearPendingWindowDragIntent() }

        let workspace = focus.workspace
        let result = try await run("workspace-layout scrolling")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(workspace.arrangement, .scrolling)
        let root = workspace.rootTilingContainer
        root.changeOrientation(.v)
        let first = TestWindow.new(id: 9420, parent: root)
        let second = TestWindow.new(id: 9421, parent: root)
        first.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 110)
        second.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 110, width: 420, height: 110)
        let mouseLocation = second.stackSplitDropZoneRect(position: .left).orDie().center
        MousePointerTracker.shared.note(point: mouseLocation)

        XCTAssertTrue(updatePendingWindowDragIntent(sourceWindow: first, mouseLocation: mouseLocation))
        XCTAssertEqual(debugPendingWindowDragIntentSummary()?.kind, .stackSplit(targetWindowId: second.windowId, position: .left))
        XCTAssertTrue(applyPendingWindowDragIntentIfPossible())

        XCTAssertEqual(root.layoutDescription, .v_tiles([.h_tiles([.window(9420), .window(9421)])]))
        XCTAssertTrue(focus.windowOrNil === first)
    }

    /// On a Tabbed workspace a drop on another group's window joins that group, resolved from the
    /// groups on screen by the Tabbed arrangement and applied through the whole pipeline.
    func testTabbedTabStackRunsThroughThePipeline() async throws {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        defer { clearPendingWindowDragIntent() }

        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let left = TestWindow.new(id: 9500, parent: root)
        let group = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .h, .tabGroup, index: INDEX_BIND_LAST)
        let tabA = TestWindow.new(id: 9501, parent: group)
        _ = TestWindow.new(id: 9502, parent: group)
        _ = left.focusWindow()
        let result = try await run("workspace-layout tabbed")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(workspace.arrangement, .tabbed)
        workspace.syncTabbedGroups()
        let first = try XCTUnwrap(workspace.tabbedGroups.first)
        XCTAssertTrue(workspace.moveTabbedTabToNewGroup(tabA.windowId, beside: first, on: .right))
        _ = left.focusWindow()
        try await workspace.layoutWorkspace()
        let right = try XCTUnwrap(workspace.tabbedGroup(containing: tabA.windowId))
        let shown = try XCTUnwrap(right.activeWindow?.lastAppliedLayoutPhysicalRect)
        let mouseLocation = CGPoint(x: shown.center.x, y: shown.center.y)
        MousePointerTracker.shared.note(point: mouseLocation)

        XCTAssertTrue(updatePendingWindowDragIntent(sourceWindow: left, mouseLocation: mouseLocation))
        XCTAssertEqual(debugPendingWindowDragIntentSummary()?.kind, .tabStack(targetWindowId: tabA.windowId))
        XCTAssertTrue(applyPendingWindowDragIntentIfPossible())

        XCTAssertTrue(workspace.tabbedGroup(containing: left.windowId) === right, "The drop joined the group it was dropped on")
        XCTAssertEqual(right.activeWindowId, left.windowId)
        XCTAssertTrue(focus.windowOrNil === left)
    }
}
