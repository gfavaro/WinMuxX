@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class DwindleResizeCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func pair() async throws -> (Workspace, TestWindow, TestWindow) {
        let workspace = focus.workspace
        workspace.rootTilingContainer.layout = .dwindle
        let first = TestWindow.new(id: 17001, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 17002, parent: workspace.rootTilingContainer)
        _ = first.focusWindow()
        try await workspace.layoutWorkspace()
        return (workspace, first, second)
    }

    func testResizeThenBalanceRestoresFramesOrderAndFocus() async throws {
        let (workspace, first, second) = try await pair()
        let original = first.lastAppliedLayoutPhysicalRect.orDie()
        let axis = original.width < workspace.rootTilingContainer.lastAppliedLayoutPhysicalRect.orDie().width ? "width" : "height"
        let resized = try await parseCommand("resize \(axis) +100").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(resized.exitCode, 0)
        try await workspace.layoutWorkspace()
        let next = first.lastAppliedLayoutPhysicalRect.orDie()
        XCTAssertEqual(axis == "width" ? next.width - original.width : next.height - original.height, 100, accuracy: 0.01)
        let balanced = try await parseCommand("balance-sizes").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(balanced.exitCode, 0)
        try await workspace.layoutWorkspace()
        XCTAssertEqual(first.lastAppliedLayoutPhysicalRect, original)
        XCTAssertEqual(workspace.rootTilingContainer.children, [first, second])
        XCTAssertTrue(focus.windowOrNil === first)
    }

    func testResizingTrailingChildGrowsItRatherThanLeadingChild() async throws {
        let (workspace, _, second) = try await pair()
        _ = second.focusWindow()
        let original = second.lastAppliedLayoutPhysicalRect.orDie()
        let result = try await parseCommand("resize smart +80").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        try await workspace.layoutWorkspace()
        let next = second.lastAppliedLayoutPhysicalRect.orDie()
        XCTAssertEqual(next.width + next.height - original.width - original.height, 80, accuracy: 0.01)
    }

    func testMouseResizeAndPreviewShareDwindleGeometry() async throws {
        let (workspace, first, _) = try await pair()
        let original = first.lastAppliedLayoutPhysicalRect.orDie()
        let split = try XCTUnwrap(first.dwindleResizeTargets().first)
        let proposed = split.orientation == .h ? original.copy(\.width, original.width + 60) : original.copy(\.height, original.height + 60)
        let map = try XCTUnwrap(proposedResizeWeightMap(first, rect: proposed))
        XCTAssertEqual(map.dwindleChanges.count, 1)
        XCTAssertTrue(map.changes.isEmpty)
        let preview = windowResizePreviewItems(in: workspace, weightMap: map, excludingActiveWindowId: nil)
        applyResizeWithMouse(first, rect: proposed)
        cancelManipulatedWithMouseState()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(first.lastAppliedLayoutPhysicalRect, proposed)
        XCTAssertEqual(preview.count, 2)
    }

    func testBalanceRecursesIntoTilesWithoutChangingTabsOrTree() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let tiles = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 0)
        let first = TestWindow.new(id: 17010, parent: tiles)
        let second = TestWindow.new(id: 17011, parent: tiles)
        first.setWeight(.h, 2)
        second.setWeight(.h, 8)
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tabGroup, index: 1)
        let tab = TestWindow.new(id: 17012, parent: tabs)
        _ = first.focusWindow()
        root.setDwindleSplitRatio(0.7, at: 0)
        let result = try await parseCommand("balance-sizes").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(root.dwindleSplitRatio(at: 0), 0.5)
        XCTAssertEqual(first.getWeight(.h), 1)
        XCTAssertEqual(second.getWeight(.h), 1)
        XCTAssertEqual(tabs.layout, .tabGroup)
        XCTAssertTrue(tab.parent === tabs)
        XCTAssertTrue(focus.windowOrNil === first)
    }

    func testRatiosPersistAndOlderSnapshotsDefaultToHalf() async throws {
        let (workspace, _, _) = try await pair()
        workspace.rootTilingContainer.setDwindleSplitRatio(0.65, at: 0)
        let data = try JSONEncoder().encode(FrozenContainer(workspace.rootTilingContainer))
        let restored = try JSONDecoder().decode(FrozenContainer.self, from: data)
        XCTAssertEqual(restored.dwindleSplitRatios, [0.65])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "dwindleSplitRatios")
        let old = try JSONDecoder().decode(FrozenContainer.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.dwindleSplitRatios)
    }

    func testExtremeResizeKeepsBothSidesVisible() async throws {
        let (workspace, first, second) = try await pair()
        let result = try await parseCommand("resize smart +999999").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(workspace.rootTilingContainer.dwindleSplitRatio(at: 0), 0.9)
        try await workspace.layoutWorkspace()
        XCTAssertGreaterThan(first.lastAppliedLayoutPhysicalRect.orDie().width, 0)
        XCTAssertGreaterThan(second.lastAppliedLayoutPhysicalRect.orDie().height, 0)
    }

    func testSplitReservesNeighbourMinimumIncludingGap() {
        XCTAssertEqual(fittedDwindleSplitLength(total: 1020, gap: 20, ratio: 0.9, minimum: 0, remainingMinimum: 300), 700)
        XCTAssertEqual(fittedDwindleSplitLength(total: 1020, gap: 20, ratio: 0.1, minimum: 350, remainingMinimum: 0), 350)
        XCTAssertEqual(fittedDwindleSplitLength(total: 1020, gap: 20, ratio: 0.7, minimum: 600, remainingMinimum: 600), 700)
    }

    func testSmartOppositeResizesOuterSplitFromLastWindow() async throws {
        let (workspace, _, _) = try await pair()
        let last = TestWindow.new(id: 17003, parent: workspace.rootTilingContainer)
        _ = last.focusWindow()
        try await workspace.layoutWorkspace()
        let targets = last.dwindleResizeTargets()
        XCTAssertEqual(targets.count, 2)
        let result = try await parseCommand("resize smart-opposite +40").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNotEqual(workspace.rootTilingContainer.dwindleSplitRatio(at: 0), 0.5)
        XCTAssertEqual(workspace.rootTilingContainer.dwindleSplitRatio(at: 1), 0.5)
    }

    func testRestoringWorldRetainsDwindleRatios() async throws {
        let (workspace, first, _) = try await pair()
        workspace.rootTilingContainer.setDwindleSplitRatio(0.65, at: 0)
        let snapshot = snapshotCurrentFrozenWorld()
        workspace.rootTilingContainer.dwindleSplitRatios = []
        let restored = try await restoreFrozenWorldIfNeeded(snapshot, newlyDetectedWindow: first)
        XCTAssertTrue(restored)
        XCTAssertEqual(workspace.rootTilingContainer.dwindleSplitRatio(at: 0), 0.65)
    }
}
