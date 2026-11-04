@testable import AppBundle
import Common
import XCTest

@MainActor
final class WindowStripTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private let group = Rect(topLeftX: 100, topLeftY: 0, width: 1000, height: 600)

    func testShowsOnlyColumnsThatFitAndFillsTheGroup() {
        let strip = WindowStripGeometry.calculate(in: group, shares: [0.5, 0.5, 0.5], gap: 10, focused: 0, firstVisible: 0)
        XCTAssertEqual(strip.visible, 0..<2)
        XCTAssertEqual(strip.frames.map(\.width), [495, 495])
        XCTAssertEqual(strip.frames.map(\.minX), [100, 605])
    }

    func testFocusScrollsOnlyAsFarAsNeeded() {
        let shares: [CGFloat] = [0.5, 0.5, 0.5, 0.5]
        XCTAssertEqual(WindowStripGeometry.calculate(in: group, shares: shares, gap: 10, focused: 2, firstVisible: 0).visible, 1..<3)
        XCTAssertEqual(WindowStripGeometry.calculate(in: group, shares: shares, gap: 10, focused: 0, firstVisible: 2).visible, 0..<2)
        XCTAssertEqual(WindowStripGeometry.calculate(in: group, shares: shares, gap: 10, focused: 2, firstVisible: 2).visible, 2..<4)
        XCTAssertEqual(WindowStripGeometry.calculate(in: group, shares: shares, gap: 10, focused: 3, firstVisible: 3).visible, 2..<4,
            "A run at the end widens backwards to fill the group")
        XCTAssertEqual(WindowStripGeometry.calculate(in: group, shares: [1, 0.5], gap: 10, focused: 0, firstVisible: 0).visible, 0..<1)
    }

    func testStripInsideDwindleShowsColumnsSideBySideAndHidesTheRest() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let left = TestWindow.new(id: 8101, parent: root)
        let strip = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tabGroup, index: INDEX_BIND_LAST)
        strip.presentsAsStrip = true
        let first = TestWindow.new(id: 8102, parent: strip)
        let second = TestWindow.new(id: 8103, parent: strip)
        let third = TestWindow.new(id: 8104, parent: strip)
        first.markAsMostRecentChild()
        try await workspace.layoutWorkspace()

        let leftRect = try XCTUnwrap(left.lastAppliedLayoutPhysicalRect)
        let firstRect = try XCTUnwrap(first.lastAppliedLayoutPhysicalRect)
        let secondRect = try XCTUnwrap(second.lastAppliedLayoutPhysicalRect)
        XCTAssertLessThan(leftRect.maxX, firstRect.minX, "The strip is a Dwindle tile beside the other window")
        XCTAssertLessThan(firstRect.maxX, secondRect.minX, "Columns sit side by side")
        XCTAssertEqual(firstRect.minY, secondRect.minY)
        XCTAssertNil(third.lastAppliedLayoutPhysicalRect, "A column that does not fit waits hidden")

        XCTAssertTrue(second.focusWindow())
        let right = try await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(right.exitCode, 0)
        XCTAssertEqual(focus.windowOrNil, third, "Focus steps into the hidden column")
        try await workspace.layoutWorkspace()
        XCTAssertNil(first.lastAppliedLayoutPhysicalRect, "The strip scrolled the first column out")
        XCTAssertEqual(try XCTUnwrap(second.lastAppliedLayoutPhysicalRect).minX, firstRect.minX)
        XCTAssertEqual(try XCTUnwrap(third.lastAppliedLayoutPhysicalRect).minX, secondRect.minX)

        let leftAgain = try await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(leftAgain.exitCode, 0)
        XCTAssertEqual(focus.windowOrNil, second, "Left stays inside the strip until its first column")

        let moveRight = try await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(moveRight.exitCode, 0)
        XCTAssertEqual(strip.children.map { ($0 as? Window)?.windowId }, [8102, 8104, 8103], "Move right reorders the strip's columns")
        XCTAssertTrue(strip.parent === root, "The window stays in the strip")
    }

    func testLayoutStripTogglesWithTabsAndSurvivesFreezing() async throws {
        let workspace = Workspace.get(byName: name)
        let group = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let first = TestWindow.new(id: 8111, parent: group)
        _ = TestWindow.new(id: 8112, parent: group)
        XCTAssertTrue(first.focusWindow())

        let strip = try XCTUnwrap(parseCommand("layout strip").cmdOrDie as? LayoutCommand)
        let stripResult = try await strip.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(stripResult.exitCode, 0)
        XCTAssertTrue(group.presentsAsStrip)
        XCTAssertEqual(group.layout, .tabGroup)
        XCTAssertFalse(group.usesDoubleSidedWindows, "Two columns stay a strip rather than a two-sided window")

        let frozen = FrozenContainer(group)
        XCTAssertEqual(frozen.presentsAsStrip, true)
        let restored = Workspace.get(byName: name + "-restored")
        XCTAssertTrue(restoreTreeRecursive(frozenContainer: frozen, parent: restored.rootTilingContainer, index: 0, windowsById: [:]))
        XCTAssertEqual((restored.rootTilingContainer.children.first as? TilingContainer)?.presentsAsStrip, true)

        let tabs = try XCTUnwrap(parseCommand("layout tab-group").cmdOrDie as? LayoutCommand)
        let tabsResult = try await tabs.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(tabsResult.exitCode, 0)
        XCTAssertFalse(group.presentsAsStrip, "tab-group shows the same group as tabs again")
        XCTAssertNil(FrozenContainer(group).presentsAsStrip)
    }
}
