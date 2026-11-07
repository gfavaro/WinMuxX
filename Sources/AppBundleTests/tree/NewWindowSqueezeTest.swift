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
