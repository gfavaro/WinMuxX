@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class MasterLayoutTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests(); config.gaps = .zero }
    override func tearDown() async throws { setUpWorkspacesForTests() }

    private func windows(_ count: Int = 4) -> [TestWindow] {
        let root = focus.workspace.rootTilingContainer
        root.layout = .tiles
        return (1...count).map { TestWindow.new(id: UInt32(23000 + $0), parent: root) }
    }
    private func command(_ text: String) async throws {
        let result = try await parseCommand(text).cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0, text)
    }

    func testFourSidesPlaceMasterAtSixtyPercentAndStackPerpendicular() async throws {
        for side in MasterSide.allCases {
            setUpWorkspacesForTests(); config.gaps = .zero; config.master.side = side
            let windows = windows()
            let workspace = focus.workspace
            workspace.configureMasterLayout(focused: windows[0])
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
            let root = workspace.rootTilingContainer
            let bounds = try XCTUnwrap(root.lastAppliedLayoutPhysicalRect)
            let master = try XCTUnwrap(windows[0].lastAppliedLayoutPhysicalRect)
            XCTAssertEqual(master.getDimension(side.orientation), bounds.getDimension(side.orientation) * 0.6, accuracy: 0.01)
            XCTAssertEqual(root.children.count, 2)
            let stack = try XCTUnwrap(root.children[1] as? TilingContainer)
            XCTAssertEqual(stack.orientation, side.orientation.opposite)
            XCTAssertEqual(stack.children, Array(windows.dropFirst()))
            XCTAssertEqual(side.orientation == .h ? master.minX : master.minY,
                side.isReversed ? (side.orientation == .h ? bounds.maxX - master.width : bounds.maxY - master.height)
                    : (side.orientation == .h ? bounds.minX : bounds.minY), accuracy: 0.01)
            let direction: CardinalDirection = side == .left ? .right : side == .right ? .left : side == .top ? .down : .up
            XCTAssertNotNil(dwindleDirectionalFocusTarget(from: windows[0], direction: direction))
        }
    }

    func testClosingMasterPromotesFirstStackPaneAndNewWindowsAppend() async throws {
        let windows = windows(3)
        let workspace = focus.workspace
        workspace.configureMasterLayout(focused: windows[0])
        windows[0].unbindFromParent()
        workspace.normalizeContainers()
        XCTAssertTrue(workspace.rootTilingContainer.children.first === windows[1])
        let binding = bindingDataForNewTilingWindow(workspace, window: nil)
        let added = TestWindow.new(id: 23999, parent: binding.parent)
        workspace.normalizeContainers()
        XCTAssertTrue(workspace.rootTilingContainer.children[1].children.last === added)
        windows[1].unbindFromParent(); windows[2].unbindFromParent()
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.rootTilingContainer.children, [added])
        XCTAssertEqual(added.lastAppliedLayoutPhysicalRect?.width, workspace.workspaceMonitor.visibleRectPaddedByOuterGaps.width)
    }

    func testMasterCommandAndSwapKeepFocusAndTabGroupsIntact() async throws {
        let windows = windows(2)
        let workspace = focus.workspace
        let tabs = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: INDEX_BIND_LAST)
        let tab = TestWindow.new(id: 23100, parent: tabs)
        TestWindow.new(id: 23101, parent: tabs)
        _ = windows[0].focusWindow()
        try await command("workspace-layout master")
        _ = tab.focusWindow()
        try await command("swap-with-master")
        XCTAssertTrue(workspace.rootTilingContainer.children.first === tabs)
        XCTAssertEqual(tabs.children.count, 2)
        XCTAssertTrue(focus.windowOrNil === tab)
        try await command("swap-with-master")
        XCTAssertTrue(workspace.rootTilingContainer.children.first === windows[1])
        _ = windows[0].focusWindow()
        try await command("workspace-layout master")
        XCTAssertTrue(workspace.rootTilingContainer.children.first === windows[0])
        try await command("workspace-layout dwindle")
        XCTAssertEqual(workspace.rootTilingContainer.layout, .dwindle)
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.allLeafWindowsRecursive.count, 4)
    }

    func testRootTabGroupBecomesOneAtomicMasterPane() {
        let windows = windows(2)
        let oldRoot = focus.workspace.rootTilingContainer
        oldRoot.layout = .tabGroup
        focus.workspace.configureMasterLayout(focused: windows[0])
        XCTAssertTrue(focus.workspace.rootTilingContainer.children.first === oldRoot)
        XCTAssertEqual(oldRoot.layout, .tabGroup)
        XCTAssertEqual(oldRoot.children, windows)
    }

    func testResizePersistsThroughNormalizationDisplayScalingAndFreeze() async throws {
        let windows = windows(2)
        let workspace = focus.workspace
        workspace.configureMasterLayout(focused: windows[0])
        try await workspace.layoutWorkspace()
        _ = windows[0].focusWindow()
        let before = try XCTUnwrap(windows[0].lastAppliedLayoutPhysicalRect)
        try await command("resize width +80")
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(windows[0].lastAppliedLayoutPhysicalRect!.width, before.width + 80, accuracy: 0.01)
        let ratio = try XCTUnwrap(workspace.rootTilingContainer.masterRatio)
        let frames = workspace.rootTilingContainer.tileChildFrames(in: Rect(topLeftX: 0, topLeftY: 0, width: 2000, height: 800),
            gaps: ResolvedGaps(gaps: .zero, monitor: workspace.workspaceMonitor))
        XCTAssertEqual(frames[0].physical.width / 2000, ratio, accuracy: 0.0001)
        let frozen = snapshotCurrentFrozenWorld()
        let decoded = try JSONDecoder().decode(FrozenWorld.self, from: JSONEncoder().encode(frozen))
        let restored = try await restoreFrozenWorldIfNeeded(decoded, newlyDetectedWindow: windows[0])
        XCTAssertTrue(restored)
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.layout, .master)
        XCTAssertEqual(workspace.rootTilingContainer.masterRatio!, ratio, accuracy: 0.0001)
        XCTAssertTrue((workspace.rootTilingContainer.children[1] as? TilingContainer)?.isMasterStack == true)
    }

    func testMousePreviewAndAppliedResizeAgreeOnEverySide() async throws {
        for side in MasterSide.allCases {
            setUpWorkspacesForTests(); config.gaps = .zero; config.master.side = side
            let windows = windows(2)
            let workspace = focus.workspace
            workspace.configureMasterLayout(focused: windows[0])
            try await workspace.layoutWorkspace()
            let before = try XCTUnwrap(windows[0].lastAppliedLayoutPhysicalRect)
            let proposal = Rect(topLeftX: before.minX - (side == .right ? 60 : 0),
                topLeftY: before.minY - (side == .bottom ? 60 : 0),
                width: before.width + (side.orientation == .h ? 60 : 0),
                height: before.height + (side.orientation == .v ? 60 : 0))
            let weights = try XCTUnwrap(proposedResizeWeightMap(windows[0], rect: proposal))
            XCTAssertEqual(weights.changes.count, 2)
            let previews = windowResizePreviewItems(in: workspace, weightMap: weights, excludingActiveWindowId: nil)
            XCTAssertEqual(previews.count, 2)
            applyResizeWithMouse(windows[0], rect: proposal)
            cancelManipulatedWithMouseState()
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
            XCTAssertEqual(windows[0].lastAppliedLayoutPhysicalRect, proposal)
        }
    }

    func testMinimumSizeFittingAndAccordionStackReuseExistingGeometry() async throws {
        let windows = windows(3)
        config.master.stackLayout = .stacked
        let workspace = focus.workspace
        workspace.configureMasterLayout(focused: windows[0])
        windows[0].testMinimumSize = CGSize(width: 700, height: 100)
        let root = workspace.rootTilingContainer
        let frames = root.tileChildFrames(in: Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 800),
            gaps: ResolvedGaps(gaps: .zero, monitor: workspace.workspaceMonitor))
        XCTAssertGreaterThanOrEqual(frames[0].physical.width, 700)
        XCTAssertEqual((root.children[1] as? TilingContainer)?.layout, .stacked)
        try await workspace.layoutWorkspace()
        XCTAssertNotNil(windows[2].lastAppliedLayoutPhysicalRect)
    }

    func testHundredsOfInsertionsAndClosuresDoNotAccumulateContainers() {
        let windows = windows(1)
        let workspace = focus.workspace
        workspace.configureMasterLayout(focused: windows[0])
        for id in 24000..<24500 {
            let binding = bindingDataForNewTilingWindow(workspace, window: nil)
            let window = TestWindow.new(id: UInt32(id), parent: binding.parent)
            workspace.normalizeContainers()
            XCTAssertEqual(workspace.rootTilingContainer.children.count, 2)
            window.unbindFromParent()
            workspace.normalizeContainers()
            XCTAssertEqual(workspace.rootTilingContainer.children, windows)
        }
    }

    func testDirectionalMoveSwapWrapAndLayoutToggleKeepMasterPolicy() async throws {
        config.master.side = .right
        let windows = windows(3)
        let workspace = focus.workspace
        workspace.configureMasterLayout(focused: windows[0])
        try await workspace.layoutWorkspace()
        _ = windows[0].focusWindow()
        let boundary = try await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertNotEqual(boundary.exitCode, 0)
        XCTAssertEqual(workspace.rootTilingContainer.layout, .master)
        try await command("swap --wrap-around right")
        XCTAssertFalse(workspace.rootTilingContainer.children.first === windows[0])
        XCTAssertTrue(focus.windowOrNil === windows[0])
        try await command("workspace-layout master dwindle")
        XCTAssertEqual(workspace.rootTilingContainer.layout, .dwindle)
        try await command("workspace-layout master dwindle")
        XCTAssertEqual(workspace.rootTilingContainer.layout, .master)
        XCTAssertTrue(workspace.rootTilingContainer.children.first === windows[0])
        try await command("balance-sizes")
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.rootTilingContainer.masterRatio!, 0.6, accuracy: 0.0001)
    }

    func testEmptyWorkspaceDefaultAndClosedStackAreNotRetained() {
        config.defaultRootContainerLayout = .master
        let workspace = Workspace.get(byName: "empty-master")
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.layout, .master)
        XCTAssertTrue(workspace.rootTilingContainer.children.isEmpty)
        let first = TestWindow.new(id: 24600, parent: workspace.rootTilingContainer)
        weak var removedStack: TilingContainer?
        do {
            let binding = bindingDataForNewTilingWindow(workspace, window: nil)
            removedStack = binding.parent as? TilingContainer
            let second = TestWindow.new(id: 24601, parent: binding.parent)
            second.unbindFromParent()
        }
        workspace.normalizeContainers()
        XCTAssertNil(removedStack)
        XCTAssertEqual(workspace.rootTilingContainer.children, [first])
    }

    func testReenteringMasterThroughPolicyDiscardsStaleModeMetadata() {
        let windows = windows(3)
        let workspace = focus.workspace
        workspace.configureMasterLayout(focused: windows[0])
        workspace.rootTilingContainer.layout = .dwindle
        _ = windows[1].focusWindow()
        workspace.rootTilingContainer.layout = .master
        workspace.normalizeMasterLayout()
        XCTAssertTrue(workspace.rootTilingContainer.children.first === windows[1])
        XCTAssertEqual(workspace.rootTilingContainer.children[1].children, [windows[0], windows[2]])
    }

    func testStackToggleFromMasterAndStackPreservesPrimaryGeometryOnEverySide() async throws {
        for side in MasterSide.allCases {
            setUpWorkspacesForTests(); config.gaps = .zero; config.master.side = side
            let panes = windows(4)
            let workspace = focus.workspace
            workspace.configureMasterLayout(focused: panes[0])
            _ = panes[0].focusWindow()
            try await workspace.layoutWorkspace()
            let root = workspace.rootTilingContainer
            let stack = try XCTUnwrap(root.children[1] as? TilingContainer)
            let original = panes[0].lastAppliedLayoutPhysicalRect
            let order = stack.children
            try await command("layout tiles accordion")
            try await workspace.layoutWorkspace()
            XCTAssertEqual(root.layout, .master)
            XCTAssertEqual(stack.layout, .stacked)
            XCTAssertEqual(stack.children, order)
            XCTAssertEqual(panes[0].lastAppliedLayoutPhysicalRect, original)
            XCTAssertTrue(focus.windowOrNil === panes[0])
            try await command("layout --window-id \(panes[2].windowId) tiles accordion")
            try await workspace.layoutWorkspace()
            XCTAssertEqual(root.layout, .master)
            XCTAssertEqual(stack.layout, .tiles)
            XCTAssertEqual(panes[0].lastAppliedLayoutPhysicalRect, original)
            XCTAssertTrue(focus.windowOrNil === panes[0])
            _ = panes[1].focusWindow()
            try await command("layout tiles accordion")
            XCTAssertEqual(stack.layout, .stacked)
            XCTAssertTrue(focus.windowOrNil === panes[1])
            try await command("layout accordion tiles")
            XCTAssertEqual(stack.layout, .tiles)
        }
    }

    func testStackToggleThroughTabGroupDoesNotChangeTheTabGroup() async throws {
        let panes = windows(2)
        let workspace = focus.workspace
        let tabs = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: INDEX_BIND_LAST)
        let tab = TestWindow.new(id: 24700, parent: tabs)
        TestWindow.new(id: 24701, parent: tabs)
        workspace.configureMasterLayout(focused: panes[0])
        _ = tab.focusWindow()
        try await command("layout tiles accordion")
        let root = workspace.rootTilingContainer
        XCTAssertEqual(root.layout, .master)
        XCTAssertEqual((root.children[1] as? TilingContainer)?.layout, .stacked)
        XCTAssertEqual(tabs.layout, .tabGroup)
        XCTAssertEqual(tabs.children.count, 2)
        XCTAssertTrue(focus.windowOrNil === tab)
        let floating = TestWindow.new(id: 24702, parent: workspace)
        let result = try await parseCommand("layout --window-id \(floating.windowId) tiles accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(root.layout, .master)
        XCTAssertEqual((root.children[1] as? TilingContainer)?.layout, .stacked)
    }

    func testEmptyStackRemembersChoiceAcrossFreezeAndRecreation() async throws {
        let panes = windows(1)
        let workspace = focus.workspace
        workspace.configureMasterLayout(focused: panes[0])
        _ = panes[0].focusWindow()
        try await command("layout tiles accordion")
        XCTAssertEqual(workspace.rootTilingContainer.children, panes)
        let snapshot = try JSONDecoder().decode(FrozenWorld.self,
            from: JSONEncoder().encode(snapshotCurrentFrozenWorld()))
        let restored = try await restoreFrozenWorldIfNeeded(snapshot, newlyDetectedWindow: panes[0])
        XCTAssertTrue(restored)
        workspace.normalizeContainers()
        weak var emptyStack: TilingContainer?
        do {
            let binding = bindingDataForNewTilingWindow(workspace, window: nil)
            let added = TestWindow.new(id: 24710, parent: binding.parent)
            XCTAssertEqual((binding.parent as? TilingContainer)?.layout, .stacked)
            emptyStack = binding.parent as? TilingContainer
            added.unbindFromParent()
        }
        workspace.normalizeContainers()
        XCTAssertNil(emptyStack)
        XCTAssertEqual(workspace.rootTilingContainer.children, panes)
        let nextBinding = bindingDataForNewTilingWindow(workspace, window: nil)
        XCTAssertEqual((nextBinding.parent as? TilingContainer)?.layout, .stacked)
    }

    func testMovingPaneIntoAnEmptyStackPreservesMasterShareAndChoice() async throws {
        let panes = windows(1)
        let workspace = focus.workspace
        workspace.configureMasterLayout(focused: panes[0])
        _ = panes[0].focusWindow()
        try await command("layout tiles accordion")
        try await workspace.layoutWorkspace()
        let source = Workspace.get(byName: "stack-move-source")
        let moved = TestWindow.new(id: 24720, parent: source.rootTilingContainer)
        try await command("move-node-to-workspace --window-id \(moved.windowId) \(workspace.name)")
        try await workspace.layoutWorkspace()
        let root = workspace.rootTilingContainer
        XCTAssertEqual(root.layout, .master)
        XCTAssertEqual(root.masterRatio!, 0.6, accuracy: 0.0001)
        XCTAssertEqual((root.children[1] as? TilingContainer)?.layout, .stacked)
        XCTAssertEqual(root.children[1].children, [moved])
        let frame = try XCTUnwrap(panes[0].lastAppliedLayoutPhysicalRect)
        let bounds = try XCTUnwrap(root.lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(frame.width / bounds.width, 0.6, accuracy: 0.0001)
    }

    func testLegacyFrozenStackInfersChoiceAndExplicitConfigChangeOverridesIt() async throws {
        let panes = windows(3)
        let workspace = focus.workspace
        workspace.configureMasterLayout(focused: panes[0])
        _ = panes[0].focusWindow()
        try await command("layout tiles accordion")
        let encoded = try JSONEncoder().encode(snapshotCurrentFrozenWorld())
        func removingNewField(_ value: Any) -> Any {
            if let dictionary = value as? [String: Any] {
                return dictionary.filter { $0.key != "masterStackLayout" }.mapValues(removingNewField)
            }
            if let array = value as? [Any] { return array.map(removingNewField) }
            return value
        }
        let legacy = try JSONSerialization.data(withJSONObject: removingNewField(JSONSerialization.jsonObject(with: encoded)))
        let snapshot = try JSONDecoder().decode(FrozenWorld.self, from: legacy)
        let restored = try await restoreFrozenWorldIfNeeded(snapshot, newlyDetectedWindow: panes[0])
        XCTAssertTrue(restored)
        workspace.normalizeContainers()
        let root = workspace.rootTilingContainer
        XCTAssertEqual((root.children[1] as? TilingContainer)?.layout, .stacked)
        config.master.size = 0.7 // An unrelated config change preserves the manual choice.
        workspace.normalizeMasterLayout()
        XCTAssertEqual((root.children[1] as? TilingContainer)?.layout, .stacked)
        try await command("layout tiles")
        XCTAssertEqual((root.children[1] as? TilingContainer)?.layout, .tiles)
        config.master.stackLayout = .stacked // An explicit new default overrides the choice.
        workspace.normalizeMasterLayout()
        XCTAssertEqual(root.masterStackLayout, .stacked)
        XCTAssertEqual((root.children[1] as? TilingContainer)?.layout, .stacked)
        try await command("workspace-layout dwindle")
        XCTAssertNil(root.masterStackLayout)
    }

    func testMasterConfigValidationAndWorkspacePolicy() {
        let parsed = parseConfig("""
        config-version = 2
        default-root-container-layout = 'master'
        [master]
        size = 0.7
        side = 'bottom'
        stack-layout = 'accordion'
        [workspace.test]
        layout = 'master'
        """)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.master.size, 0.7)
        XCTAssertEqual(parsed.config.master.side, .bottom)
        XCTAssertEqual(parsed.config.master.stackLayout, .stacked)
        XCTAssertEqual(parsed.config.workspaceLayouts["test"]?.defaults.layout, .master)
        for entry in ["size = 0", "size = 1", "size = nan", "size = '0.6'", "side = 'middle'", "stack-layout = 'dwindle'"] {
            XCTAssertFalse(parseConfig("[master]\n\(entry)").errors.isEmpty, entry)
        }
    }
}
