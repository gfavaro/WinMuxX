@testable import AppBundle
import XCTest

final class NewWindowSqueezeTest: XCTestCase {
    func testSplitsWhenBothHalvesFitTheMinimums() {
        XCTAssertFalse(newWindowSplitWouldSqueeze(tile: CGSize(width: 1700, height: 1000),
            gap: CGSize(width: 10, height: 10), minimumExtents: [800, 0]))
        XCTAssertFalse(newWindowSplitWouldSqueeze(tile: CGSize(width: 1700, height: 1000),
            gap: .zero, minimumExtents: []), "Without learned minimums the window splits as before")
    }

    func testJoinsWhenEitherSideWouldGoBelowItsMinimum() {
        XCTAssertTrue(newWindowSplitWouldSqueeze(tile: CGSize(width: 1000, height: 1000), gap: CGSize(width: 10, height: 10),
            minimumExtents: [300, 500]), "A square tile splits side by side: 495 points is narrower than 500")
        XCTAssertTrue(newWindowSplitWouldSqueeze(tile: CGSize(width: 600, height: 900), gap: CGSize(width: 10, height: 10),
            minimumExtents: [500, 0]), "A tall tile splits top and bottom, so the height decides")
    }
}

/// Uses the workspace world, so the fixture is reset before and after.
final class NewWindowSqueezeTabGroupTest: WorkspaceTestCase {
    @MainActor
    func testATabGroupCountsItsHiddenTabsAndChrome() {
        let root = Workspace.get(byName: "squeeze").rootTilingContainer
        let group = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .h, .tabGroup, index: INDEX_BIND_LAST)
        let front = TestWindow.new(id: 1, parent: group)
        let hidden = TestWindow.new(id: 2, parent: group)
        front.markAsMostRecentChild()
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 800)
        hidden.testMinimumSize = CGSize(width: 700, height: 300)
        XCTAssertGreaterThanOrEqual(group.minimumLayoutExtent(along: .h, rect: rect), 700,
            "A hidden tab's larger minimum decides the group's minimum")
    }
}

final class NewWindowRowSqueezeTest: XCTestCase {
    func testAnotherRowFitsWhileEveryShareMeetsItsMinimum() {
        XCTAssertFalse(newWindowRowWouldSqueeze(extent: 1080, gap: 0, tiles: 2, minimumExtents: [300, 300, 0]),
            "Three rows of 360 points hold 300-point minimums")
        XCTAssertTrue(newWindowRowWouldSqueeze(extent: 1080, gap: 0, tiles: 2, minimumExtents: [500, 300, 0]),
            "A third row of 360 points is shorter than 500")
        XCTAssertEqual(newWindowRowWouldSqueeze(extent: 1000, gap: 10, tiles: 1, minimumExtents: [495]),
            newWindowSplitWouldSqueeze(tile: CGSize(width: 1000, height: 600), gap: CGSize(width: 10, height: 10),
                minimumExtents: [495]), "Halving a tile is a row of one tile gaining another")
    }
}

@MainActor
final class NewWindowMasterStackTest: WorkspaceTestCase {
    private func masterWorkspace(stackMinimumHeight: CGFloat) -> (Workspace, main: Window, stack: [Window]) {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let main = TestWindow.new(id: 75001, parent: root)
        let stack = [TestWindow.new(id: 75002, parent: root), TestWindow.new(id: 75003, parent: root)]
        stack.forEach { $0.testMinimumSize = CGSize(width: 100, height: stackMinimumHeight) }
        workspace.transitionArrangement(to: .master, focused: main)
        _ = stack[1].focusWindow()
        stack[1].markAsMostRecentChild()
        return (workspace, main, stack)
    }

    func testAFullStackGivesTheNewWindowATabInTheWindowInUse() {
        let (workspace, _, stack) = masterWorkspace(stackMinimumHeight: 500)
        let binding = bindingDataForNewTilingWindow(workspace, window: nil, newlyOpenedBundleId: .some(nil))
        let group = binding.parent as? TilingContainer
        XCTAssertEqual(group?.layout, .tabGroup, "A third stack row would be shorter than 500 points")
        XCTAssertTrue(stack[1].parent === group, "The window in use starts the tab group")
        XCTAssertEqual(workspace.workspaceLayoutUnits.count, 3, "The stack keeps its two rows")
    }

    func testAStackWithRoomAddsARow() {
        let (workspace, _, _) = masterWorkspace(stackMinimumHeight: 300)
        let binding = bindingDataForNewTilingWindow(workspace, window: nil, newlyOpenedBundleId: .some(nil))
        XCTAssertTrue(binding.parent === workspace.rootTilingContainer)
        XCTAssertNotEqual((binding.parent as? TilingContainer)?.layout, .tabGroup)
    }

    func testAMovedWindowStillAddsARow() {
        let (workspace, _, _) = masterWorkspace(stackMinimumHeight: 500)
        let binding = bindingDataForNewTilingWindow(workspace, window: nil)
        XCTAssertTrue(binding.parent === workspace.rootTilingContainer, "Explicit moves keep their placement")
    }
}
