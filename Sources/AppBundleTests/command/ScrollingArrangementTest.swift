@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class ScrollingArrangementTest: WorkspaceTestCase {
    private func run(_ text: String) async throws -> CmdResult {
        try await XCTUnwrap(parseCommand(text).cmdOrDie).run(.defaultEnv, .emptyStdin)
    }

    private func succeed(_ text: String) async throws {
        let result = try await run(text)
        XCTAssertEqual(result.exitCode, 0, text)
    }

    private func strip(_ count: Int) async throws -> (Workspace, [Window]) {
        let workspace = focus.workspace
        workspace.rootTilingContainer.layout = .tiles
        let windows = (0..<count).map { TestWindow.new(id: UInt32(76000 + $0), parent: workspace.rootTilingContainer) }
        _ = windows[0].focusWindow()
        try await succeed("workspace-layout scrolling")
        XCTAssertEqual(workspace.arrangement, .scrolling)
        return (workspace, windows)
    }

    func testEachGroupIsAColumnAndColumnsPastTheDisplayAreParkedAtItsEdge() async throws {
        let (workspace, windows) = try await strip(4)
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
        let display = workspaceTilingRect(workspace)
        let frames = workspace.arrangementGroupFrames(in: display, gaps: gaps)
        XCTAssertEqual(frames.map { ($0.node as? Window)?.windowId }, windows.map(\.windowId))
        XCTAssertEqual(frames[1].virtual.width, frames[2].virtual.width, accuracy: 1, "Columns share the default width")
        XCTAssertLessThan(frames[0].virtual.minX, frames[1].virtual.minX)
        let past = frames[3]
        XCTAssertGreaterThan(past.virtual.minX, display.maxX, "The fourth half-width column is past the display")
        XCTAssertLessThan(past.physical.minX, display.maxX + 1, "macOS keeps it at the edge, previewed")
    }

    func testFocusScrollsTheStripToTheColumn() async throws {
        let (workspace, windows) = try await strip(4)
        workspace.scrollToFocusedColumnIfNeeded()
        XCTAssertEqual(workspace.scrollingOffset, 0, accuracy: 0.5)
        _ = windows[3].focusWindow()
        workspace.scrollToFocusedColumnIfNeeded()
        let metrics = workspace.scrollingMetrics
        let column = try XCTUnwrap(metrics.columns.last)
        XCTAssertGreaterThan(workspace.scrollingOffset, 0)
        XCTAssertLessThanOrEqual(column.start + column.width, workspace.scrollingOffset + metrics.areaWidth + 0.5,
                                 "The focused column is wholly in view")
    }

    func testFocusAndMoveStepThroughColumns() async throws {
        let (workspace, windows) = try await strip(3)
        try await succeed("focus right")
        XCTAssertTrue(focus.windowOrNil === windows[1])
        try await succeed("move left")
        XCTAssertEqual(workspace.workspaceLayoutUnits.map { ($0 as? Window)?.windowId }, [76001, 76000, 76002],
                       "Moving left swaps the column with its neighbour")
        XCTAssertTrue(focus.windowOrNil === windows[1])
    }

    func testResizeChangesTheColumnShare() async throws {
        let (workspace, windows) = try await strip(3)
        let before = try XCTUnwrap(workspace.scrollingMetrics.columns.first).width
        try await succeed("resize width +100")
        XCTAssertNotNil(windows[0].scrollingColumnWidth)
        XCTAssertEqual(try XCTUnwrap(workspace.scrollingMetrics.columns.first).width, before + 100, accuracy: 2)
    }

    func testNewWindowIsAColumnRightOfTheFocusedOne() async throws {
        let (workspace, windows) = try await strip(3)
        _ = windows[1].focusWindow()
        let binding = bindingDataForNewTilingWindow(workspace, window: nil, newlyOpenedBundleId: .some(nil))
        XCTAssertTrue(binding.parent === workspace.arrangementGroupParent)
        XCTAssertEqual(binding.index, 2)
    }

    func testReturningToDwindleKeepsTheTree() async throws {
        let (workspace, windows) = try await strip(3)
        let root = workspace.rootTilingContainer
        let children = root.children
        try await succeed("workspace-layout dwindle")
        XCTAssertEqual(root.children, children)
        XCTAssertTrue(root.allLeafWindowsRecursive.elementsEqual(windows, by: ===))
    }

    func testWidthCommandStepsThroughThePresets() async throws {
        let (_, windows) = try await strip(2)
        try await succeed("scrolling-width next")
        XCTAssertEqual(windows[0].scrollingColumnWidth ?? 0, 0.7, accuracy: 0.001)
        try await succeed("scrolling-width next")
        XCTAssertEqual(windows[0].scrollingColumnWidth ?? 0, 1, accuracy: 0.001)
        try await succeed("scrolling-width next")
        XCTAssertEqual(windows[0].scrollingColumnWidth ?? 0, 0.33, accuracy: 0.001, "Next wraps around to the first preset")
        try await succeed("scrolling-width previous")
        XCTAssertEqual(windows[0].scrollingColumnWidth ?? 0, 1, accuracy: 0.001, "Previous wraps around to the last preset")
        try await succeed("scrolling-width full")
        XCTAssertEqual(windows[0].scrollingColumnWidth, 1)
        try await succeed("scrolling-width 0.4")
        XCTAssertEqual(windows[0].scrollingColumnWidth ?? 0, 0.4, accuracy: 0.001)
    }

    func testFocusAndMoveByPlace() async throws {
        let (workspace, windows) = try await strip(4)
        try await succeed("scrolling-focus last")
        XCTAssertTrue(focus.windowOrNil === windows[3])
        try await succeed("scrolling-move first")
        XCTAssertTrue(workspace.workspaceLayoutUnits.first === windows[3])
        try await succeed("scrolling-focus 2")
        XCTAssertTrue(focus.windowOrNil === windows[0])
    }

    func testPanScrollsWithoutMovingFocusAndFocusBringsItBack() async throws {
        let (workspace, windows) = try await strip(4)
        workspace.scrollToFocusedColumnIfNeeded()
        try await succeed("scrolling-pan right")
        XCTAssertGreaterThan(workspace.scrollingOffset, 0)
        XCTAssertTrue(focus.windowOrNil === windows[0])
        workspace.scrollToFocusedColumnIfNeeded()
        XCTAssertGreaterThan(workspace.scrollingOffset, 0, "A layout after a pan does not scroll back to the focus")
        try await succeed("scrolling-pan focus")
        XCTAssertEqual(workspace.scrollingOffset, 0, accuracy: 0.5)
    }

    func testDraggingAWindowEdgeSetsItsColumnWidth() async throws {
        let (workspace, windows) = try await strip(3)
        try await workspace.layoutWorkspace()
        let before = try XCTUnwrap(workspace.scrollingColumnWidthRange(of: windows[0])).width
        let shown = try XCTUnwrap(windows[0].lastAppliedLayoutPhysicalRect)
        applyResizeWithMouse(windows[0], rect: Rect(topLeftX: shown.minX, topLeftY: shown.minY,
                                                   width: shown.width + 120, height: shown.height - 50))
        cancelManipulatedWithMouseState()
        XCTAssertEqual(try XCTUnwrap(workspace.scrollingColumnWidthRange(of: windows[0])).width, before + 120, accuracy: 2)
        XCTAssertEqual(windows[0].parent === workspace.rootTilingContainer, true, "The window stays tiled")
    }

    func testChangingLayoutEndsAStripPan() async throws {
        let (workspace, _) = try await strip(2)
        workspace.scrollingGestureMotionActive = true
        workspace.scrollingGestureSessionID = UUID()
        try await succeed("workspace-layout dwindle")
        XCTAssertFalse(workspace.scrollingGestureMotionActive)
        XCTAssertNil(workspace.scrollingGestureSessionID)
    }

    func testCommandsRefuseOtherLayouts() async throws {
        let workspace = focus.workspace
        _ = TestWindow.new(id: 76100, parent: workspace.rootTilingContainer).focusWindow()
        for command in ["scrolling-width next", "scrolling-center", "scrolling-pan left", "scrolling-focus 1", "scrolling-move last"] {
            let result = try await run(command)
            XCTAssertNotEqual(result.exitCode, 0, command)
        }
    }

    func testASwipeSettlesOnTheNearestColumnAndAlwaysAdvancesAtLeastOne() async throws {
        let (workspace, windows) = try await strip(4)
        windows[0].scrollingColumnWidth = 1 // the first column fills the display, so it is nearest at the start
        let metrics = workspace.scrollingMetrics
        let second = metrics.columns[1], first = metrics.columns[0]
        let nearSecond = second.start + second.width / 2 - metrics.areaWidth / 2
        XCTAssertTrue(nearestScrollingColumn(in: metrics, offset: nearSecond, direction: 1)?.node === second.node)
        let stuck = settledDockSwipeColumn(in: metrics, offset: 0, direction: 1,
                                           startingColumnID: ObjectIdentifier(first.node), advanceIfStuck: true)
        XCTAssertTrue(stuck?.node === second.node, "A committed swipe that has not left the first column still advances")
        let atEnd = settledDockSwipeColumn(in: metrics, offset: 0, direction: -1,
                                           startingColumnID: ObjectIdentifier(first.node), advanceIfStuck: true)
        XCTAssertTrue(atEnd?.node === first.node, "Nothing past the first column")
    }
}

@MainActor
final class ScrollingDefaultLayoutTest: WorkspaceTestCase {
    func testScrollingAsTheDefaultStartsNewWorkspacesAsAStrip() {
        let parsed = parseConfig("default-root-container-layout = 'scrolling'")
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.defaultRootLayoutChoice, .scrolling)
        XCTAssertEqual(parsed.config.defaultRootContainerLayout, .tiles, "The tree under the strip is plain tiles")
        config.defaultRootLayoutChoice = .scrolling
        XCTAssertEqual(Workspace.get(byName: "fresh-scrolling").arrangement, .scrolling)
        config.defaultRootLayoutChoice = .container(.dwindle)
        XCTAssertEqual(Workspace.get(byName: "fresh-dwindle").arrangement, .dwindle)
        XCTAssertEqual(parseConfig("default-root-container-layout = 'master'").config.defaultRootLayoutChoice, .container(.master))
    }
}
