@testable import AppBundle
import XCTest

@MainActor
final class ExistingDwindleWindowsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testStartupKeepsDwindleForMoreThanThreeAlreadyOpenWindows() async throws {
        config.defaultRootContainerLayout = .dwindle
        config.defaultRootContainerOrientation = .auto
        config.enableNormalizationFlattenContainers = true
        config.enableNormalizationOppositeOrientationForNestedContainers = true
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let windows = (1...4).map { TestWindow.new(id: UInt32(1100 + $0), parent: root) }

        applyStartupWindowLayout(restoredWorld: false)
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()

        XCTAssertTrue(workspace.rootTilingContainer === root)
        XCTAssertEqual(root.layout, .dwindle)
        let frames = windows.map { $0.lastAppliedLayoutPhysicalRect.orDie() }
        XCTAssertLessThan(frames[0].minX, frames[1].minX)
        XCTAssertEqual(frames[1].minX, frames[2].minX)
        XCTAssertLessThan(frames[1].minY, frames[2].minY)
        XCTAssertEqual(frames[2].minY, frames[3].minY)
        XCTAssertLessThan(frames[2].minX, frames[3].minX)
    }

    func testStartupUpgradesOldTiledRootsOnAllWorkspacesIncludingRestoredState() {
        let first = focus.workspace
        let second = Workspace.get(byName: "other-display")
        let firstRoot = first.rootTilingContainer
        let secondRoot = second.rootTilingContainer
        TestWindow.new(id: 1110, parent: firstRoot)
        TestWindow.new(id: 1111, parent: secondRoot)
        config.defaultRootContainerLayout = .dwindle

        applyStartupWindowLayout(restoredWorld: true)

        XCTAssertEqual(firstRoot.layout, .dwindle)
        XCTAssertEqual(secondRoot.layout, .dwindle)
        XCTAssertEqual(firstRoot.allLeafWindowsRecursive.map(\.windowId), [1110])
        XCTAssertEqual(secondRoot.allLeafWindowsRecursive.map(\.windowId), [1111])
    }

    func testMigrationPreservesFloatingWindowsAndNestedAndRootTabGroups() {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let tabbed = TestWindow.new(id: 1120, parent: tabs)
        let floating = TestWindow.new(id: 1121, parent: workspace)
        let other = Workspace.get(byName: "tabs")
        let otherRoot = other.rootTilingContainer
        otherRoot.layout = .tabGroup
        TestWindow.new(id: 1122, parent: otherRoot)
        config.defaultRootContainerLayout = .dwindle

        applyStartupWindowLayout(restoredWorld: true)

        XCTAssertEqual(root.layout, .dwindle)
        XCTAssertTrue(tabbed.parent === tabs)
        XCTAssertEqual(tabs.layout, .tabGroup)
        XCTAssertTrue(floating.parent === workspace)
        XCTAssertEqual(otherRoot.layout, .tabGroup)
    }

    func testRestoredOldTreeUsesDwindleForExistingAndNextWindow() async throws {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 1150, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 1151, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 1152, parent: workspace.rootTilingContainer)
        let oldState = snapshotCurrentFrozenWorld()
        config.defaultRootContainerLayout = .dwindle
        let restored = try await restoreFrozenWorldIfNeeded(oldState, newlyDetectedWindow: first)
        XCTAssertTrue(restored)
        XCTAssertEqual(workspace.rootTilingContainer.layout, .tiles)

        applyStartupWindowLayout(restoredWorld: true)
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.rootTilingContainer.layout, .dwindle)
        XCTAssertEqual(workspace.rootTilingContainer.allLeafWindowsRecursive.count, 3)

        first.markAsMostRecentChild()
        let binding = bindingDataForNewRegularWindow(workspace, window: nil)
        let fourth = TestWindow.new(id: 1153, parent: binding.parent, adaptiveWeight: binding.adaptiveWeight)
        XCTAssertTrue(first.parent === fourth.parent)
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.rootTilingContainer.layout, .dwindle)
        XCTAssertEqual(workspace.rootTilingContainer.allLeafWindowsRecursive.count, 4)
    }

    func testEnablingDwindleAtRuntimeUpdatesExistingRootsButUnrelatedReloadDoesNotOverrideManualLayout() {
        let root = focus.workspace.rootTilingContainer
        TestWindow.new(id: 1130, parent: root)
        let previouslyReady = isWinMuxRuntimeReady
        isWinMuxRuntimeReady = true
        defer { isWinMuxRuntimeReady = previouslyReady }
        config.defaultRootContainerLayout = .dwindle

        applyUpdatedDefaultWindowLayout(previousLayout: .tiles)
        XCTAssertEqual(root.layout, .dwindle)
        root.layout = .tiles // A subsequent manual layout selection.
        applyUpdatedDefaultWindowLayout(previousLayout: .dwindle)
        focus.workspace.normalizeContainers()
        XCTAssertEqual(root.layout, .tiles)
    }

    func testStartupWithAutomaticTilingDisabledLeavesExistingFloatingWindowsFloating() {
        let workspace = focus.workspace
        let floating = TestWindow.new(id: 1140, parent: workspace)
        config.defaultRootContainerLayout = .dwindle
        config.automaticallyTileNewWindows = false

        applyStartupWindowLayout(restoredWorld: false)

        XCTAssertTrue(floating.parent === workspace)
        XCTAssertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.isEmpty)
    }
}
