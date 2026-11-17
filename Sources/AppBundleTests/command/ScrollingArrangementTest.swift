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
}
