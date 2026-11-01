@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class ScrollingStripFeaturesTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    /// Five 0.4-wide columns: the strip overflows the screen.
    private func strip() async throws -> (Workspace, [TestWindow]) {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .tiles
        let windows = (0..<5).map { TestWindow.new(id: UInt32(8100 + $0), parent: workspace.rootTilingContainer) }
        windows.forEach { $0.scrollingColumnWidth = 0.4 }
        workspace.transitionArrangement(to: .scrolling)
        _ = windows[0].focusWindow()
        try await workspace.layoutWorkspace()
        return (workspace, windows)
    }

    private func run(_ text: String) async throws -> Int32 {
        try await XCTUnwrap(parseCommand(text).unwrap().0).run(.defaultEnv, .emptyStdin).exitCode
    }

    func testSettingsParse() {
        let parsed = parseConfig("""
        [scrolling]
        center-focused-column = 'on-overflow'
        minimap-hold-modifiers = ['ctrl', 'alt']
        """)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.scrolling.centerFocusedColumn, .onOverflow)
        XCTAssertEqual(parsed.config.scrolling.minimapHoldModifiers, [.control, .option])
        XCTAssertFalse(parseConfig("[scrolling]\ncenter-focused-column = 'sometimes'").errors.isEmpty)
    }

    func testCentreModes() async throws {
        let (workspace, _) = try await strip()
        let metrics = workspace.scrollingMetrics
        let visible = metrics.columns[0]
        let offscreen = metrics.columns[4]
        let current = metrics.clampedOffset(0)
        XCTAssertEqual(metrics.focusedOffset(for: visible, current: current, mode: .never), current)
        XCTAssertEqual(metrics.focusedOffset(for: visible, current: current, mode: .onOverflow), current, "Already visible: stays")
        XCTAssertEqual(metrics.focusedOffset(for: offscreen, current: current, mode: .onOverflow), metrics.centeredOffset(for: offscreen))
        XCTAssertEqual(metrics.focusedOffset(for: offscreen, current: current, mode: .never), metrics.revealedOffset(for: offscreen, current: current))
        XCTAssertEqual(metrics.focusedOffset(for: metrics.columns[2], current: current, mode: .always), metrics.centeredOffset(for: metrics.columns[2]))
    }

    func testFocusAndMoveByPlaceOnTheStrip() async throws {
        let (workspace, windows) = try await strip()
        let code1 = try await run("scrolling-focus 3")

        XCTAssertEqual(code1, 0)
        XCTAssertEqual(focus.windowOrNil?.windowId, windows[2].windowId)
        let code2 = try await run("scrolling-focus 9")

        XCTAssertEqual(code2, 0, "9 is the last column, like browser tabs")
        XCTAssertEqual(focus.windowOrNil?.windowId, windows[4].windowId)
        let code3 = try await run("scrolling-move first")

        XCTAssertEqual(code3, 0)
        XCTAssertEqual(workspace.scrollingStripUnits.first.map { ObjectIdentifier($0) }, ObjectIdentifier(windows[4]))
        let code4 = try await run("scrolling-focus 8")

        XCTAssertNotEqual(code4, 0, "No eighth column on a five-column strip")
    }

    func testPinnedColumnHoldsItsEdgeAndLeavesTheStrip() async throws {
        let (workspace, windows) = try await strip()
        _ = windows[1].focusWindow()
        let code5 = try await run("scrolling-pin left")

        XCTAssertEqual(code5, 0)
        XCTAssertTrue(workspace.pinnedScrollingColumn === windows[1])
        XCTAssertFalse(workspace.scrollingStripUnits.contains { $0 === windows[1] }, "The strip scrolls without it")
        try await workspace.layoutWorkspace()
        let rect = workspaceTilingRect(workspace)
        let pinned = try XCTUnwrap(windows[1].lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(pinned.minX, rect.minX, accuracy: 1, "Held at the left edge")
        XCTAssertEqual(pinned.height, rect.height, accuracy: 1, "Full height")
        XCTAssertFalse(windows[1].isConcealedByScrolling)
        let stripStart = try XCTUnwrap(workspace.scrollingMetrics.geometry.area.minX as CGFloat?)
        XCTAssertGreaterThan(stripStart, pinned.maxX, "The strip starts beside it")
        // The pin line sits in the gap between the pinned column and the strip.
        let line = ScrollingPinIndicator.lineRect(pinned: pinned, side: .left, gap: stripStart - pinned.maxX)
        XCTAssertGreaterThanOrEqual(line.minX, pinned.maxX)
        XCTAssertLessThanOrEqual(line.maxX, stripStart)
        XCTAssertGreaterThan(line.minY, pinned.minY)
        XCTAssertLessThan(line.maxY, pinned.maxY)
        let right = ScrollingPinIndicator.lineRect(pinned: pinned, side: .right, gap: 10)
        XCTAssertEqual(right.maxX, pinned.minX - 5 + ScrollingPinIndicator.thickness / 2, accuracy: 0.01)
        // Scrolling far right keeps the pinned column in place.
        workspace.scrollingOffset = .greatestFiniteMagnitude
        try await workspace.layoutWorkspace()
        XCTAssertEqual(windows[1].lastAppliedLayoutPhysicalRect, pinned)
        let code6 = try await run("scrolling-pin left")

        XCTAssertEqual(code6, 0)
        XCTAssertNil(workspace.pinnedScrollingColumn, "The same command unpins")
    }

    func testAStripMovedForASheetSettlesBackUnlessSomethingElseMovedIt() {
        // A sheet opens: the strip moves to show it, remembering where it was.
        var step = ScrollingSheetReveal.step(current: 100, windowId: 7, target: 260, remembered: nil)
        XCTAssertEqual(step.offset, 260)
        XCTAssertEqual(step.remembered, ScrollingSheetReveal(windowId: 7, before: 100, revealed: 260))
        // Still open, dragged wider: it follows, still remembering the first place.
        step = ScrollingSheetReveal.step(current: 260, windowId: 7, target: 300, remembered: step.remembered)
        XCTAssertEqual(step.remembered?.before, 100)
        // Closed: back where it was.
        let closed = ScrollingSheetReveal.step(current: 300, windowId: 7, target: nil, remembered: step.remembered)
        XCTAssertEqual(closed.offset, 100)
        XCTAssertNil(closed.remembered)
        // Panned meanwhile, or another window focused: the strip stays put.
        XCTAssertEqual(ScrollingSheetReveal.step(current: 500, windowId: 7, target: nil, remembered: step.remembered).offset, 500)
        XCTAssertEqual(ScrollingSheetReveal.step(current: 300, windowId: 8, target: nil, remembered: step.remembered).offset, 300)
        // A sheet that already fits moves nothing and remembers nothing.
        XCTAssertNil(ScrollingSheetReveal.step(current: 100, windowId: 7, target: 100, remembered: nil).remembered)
    }

    func testMinimapDragReordersStripColumns() async throws {
        let (workspace, windows) = try await strip()
        workspace.moveScrollingColumn(ObjectIdentifier(windows[0]), toStripIndex: 3)
        XCTAssertEqual(workspace.scrollingStripUnits.map { ($0 as? Window)?.windowId }, [8101, 8102, 8103, 8100, 8104])
    }
}

@MainActor
final class ScrollingJoinTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testJoiningRightFromAStackKeepsColumnOrder() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let stack = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: 0)
        let upper = TestWindow.new(id: 8501, parent: stack)
        let lower = TestWindow.new(id: 8502, parent: stack)
        let neighbor = TestWindow.new(id: 8503, parent: root)
        workspace.transitionArrangement(to: .scrolling)
        XCTAssertTrue(lower.focusWindow())
        let result = try await XCTUnwrap(parseCommand("join-with right").unwrap().0).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined())
        let columns = workspace.scrollingStripUnits
        XCTAssertEqual(columns.count, 2)
        XCTAssertTrue(columns[0] === upper || columns[0].allLeafWindowsRecursive == [upper], "The stack stays first")
        XCTAssertEqual(Set(columns[1].allLeafWindowsRecursive.map(\.windowId)), [lower.windowId, neighbor.windowId],
            "The joined pair takes the neighbour's place, to the right")
    }
}
