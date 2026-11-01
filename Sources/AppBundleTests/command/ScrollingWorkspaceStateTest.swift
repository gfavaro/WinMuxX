@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class ScrollingWorkspaceStateTest: WorkspaceTestCase {
    private func run(_ text: String) async throws {
        let result = try await XCTUnwrap(parseCommand(text).cmdOrNil).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined())
    }

    func testMinimumSwallowedResizeKeepsPreferredWidthAndNormalResizeUsesContentWidth() async throws {
        let workspace = focus.workspace
        let a = TestWindow.new(id: 98101, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 98102, parent: workspace.rootTilingContainer)
        workspace.transitionArrangement(to: .scrolling)
        a.scrollingColumnWidth = 0.3
        a.testMinimumSize = CGSize(width: 1200, height: 0)
        _ = a.focusWindow()
        let width = try XCTUnwrap(workspace.scrollingMetrics.columns.first).width
        try await run("resize width -10")
        try await run("resize smart -10")
        XCTAssertEqual(a.scrollingColumnWidth, 0.3)
        XCTAssertEqual(try XCTUnwrap(workspace.scrollingMetrics.columns.first).width, width)
        a.testMinimumSize = .zero
        a.scrollingColumnWidth = 0.3
        let before = try XCTUnwrap(workspace.scrollingMetrics.columns.first).width
        try await run("resize width +80")
        XCTAssertEqual(try XCTUnwrap(workspace.scrollingMetrics.columns.first).width, before + 80, accuracy: 1)
    }

    func testWorkspaceControlsPreviewReadsFramesWithoutChangingScrollingOffset() {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 98109, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 98110, parent: workspace.rootTilingContainer)
        workspace.transitionArrangement(to: .scrolling)
        _ = first.focusWindow()
        workspace.scrollingOffset = 123
        let snapshot = WorkspaceControlsPanelController.shared.makeSnapshot()
        XCTAssertEqual(snapshot?.workspaceId, workspace.id)
        XCTAssertEqual(workspace.scrollingOffset, 123)
    }

    func testTabAndAccordionRootTransitionsAndNewInsertionPreserveAtomicGroup() async throws {
        for layout in [Layout.tabGroup, .stacked] {
            let workspace = Workspace.get(byName: "atomic-\(layout.rawValue)")
            let atomic = workspace.rootTilingContainer
            atomic.layout = layout
            let a = TestWindow.new(id: layout == .tabGroup ? 98111 : 98121, parent: atomic)
            let b = TestWindow.new(id: layout == .tabGroup ? 98112 : 98122, parent: atomic)
            workspace.transitionArrangement(to: .scrolling)
            XCTAssertEqual(workspace.workspaceLayoutUnits, [atomic])
            XCTAssertEqual(atomic.layout, layout)
            XCTAssertEqual(atomic.children, [a, b])
            config.autoAddNewWindowsToTabGroup = false
            let binding = bindingDataForNewTilingWindow(workspace, window: nil)
            XCTAssertTrue(binding.parent === workspace.rootTilingContainer)
            XCTAssertFalse(binding.parent === atomic)
            workspace.transitionArrangement(to: .master)
            workspace.transitionArrangement(to: .dwindle)
            workspace.normalizeContainers()
            XCTAssertTrue(workspace.rootTilingContainer.children.first === atomic)
            XCTAssertEqual(atomic.layout, layout)
            XCTAssertEqual(atomic.children, [a, b])
        }
    }

    func testBackgroundInsertionPreservesViewportAndTabPreference() throws {
        let workspace = focus.workspace
        let tabs = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let a = TestWindow.new(id: 98131, parent: tabs)
        TestWindow.new(id: 98132, parent: tabs)
        workspace.transitionArrangement(to: .scrolling)
        _ = a.focusWindow()
        workspace.scrollingOffset = 17
        config.autoAddNewWindowsToTabGroup = true
        let tabBinding = bindingDataForNewTilingWindow(workspace, window: nil)
        XCTAssertTrue(tabBinding.parent === tabs)
        config.autoAddNewWindowsToTabGroup = false
        let columnBinding = bindingDataForNewTilingWindow(workspace, window: nil)
        XCTAssertTrue(columnBinding.parent === workspace.rootTilingContainer)
        XCTAssertEqual(columnBinding.index, 1)
        XCTAssertTrue(focus.windowOrNil === a)
        XCTAssertEqual(workspace.scrollingOffset, 17)
    }

    func testRecoveryUsesSnapshotMappingAcrossChangedNativeIDsAndDisplaySize() async throws {
        let workspace = focus.workspace
        let old = (0..<4).map { TestWindow.new(id: UInt32(98140 + $0), parent: workspace.rootTilingContainer) }
        workspace.transitionArrangement(to: .scrolling)
        old.forEach { $0.scrollingColumnWidth = 0.7 }
        _ = old[2].focusWindow()
        workspace.scrollingOffset = workspace.scrollingMetrics.centeredOffset(for: workspace.scrollingMetrics.columns[2])
        workspace.lastScrollingFocusWindowId = old[2].windowId
        let snapshot = try JSONDecoder().decode(FrozenWorkspace.self, from: JSONEncoder().encode(FrozenWorkspace(workspace)))
        let relative = try XCTUnwrap(snapshot.scrollingAnchorViewportPosition)
        old.forEach { $0.unbindFromParent() }
        let current = (0..<4).map { TestWindow.new(id: UInt32(98240 + $0), parent: workspace.rootTilingContainer) }
        _ = current[2].focusWindow()
        let point = workspace.workspaceMonitor.rect.topLeftCorner
        let rect = Rect(topLeftX: point.x, topLeftY: point.y, width: 2400, height: 1400)
        setMonitorsForTests([TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "Restored", rect: rect, visibleRect: rect, isMain: true)])
        let map = Dictionary(uniqueKeysWithValues: zip(old, current).map { ($0.windowId, $1 as Window) })
        let restored = try await restoreFrozenWorldIfNeeded(
            FrozenWorld(workspaces: [snapshot], monitors: [], windowIds: Set(old.map(\.windowId))),
            newlyDetectedWindow: current[0], matchedWindows: map, restoreVisibleWorkspaces: false)
        XCTAssertTrue(restored)
        let metrics = workspace.scrollingMetrics
        let column = try XCTUnwrap(metrics.columns.first { $0.node === current[2] })
        XCTAssertEqual(workspace.lastScrollingFocusWindowId, current[2].windowId)
        XCTAssertEqual(workspace.scrollingOffset, metrics.clampedOffset(column.start + column.width / 2 - relative * metrics.areaWidth), accuracy: 0.01)
        XCTAssertEqual(Set(workspace.allLeafWindowsRecursive.map(\.windowId)), Set(current.map(\.windowId)))
        XCTAssertTrue(current.allSatisfy { $0.scrollingColumnWidth == 0.7 })
    }

    func testWholeWorkspaceMoveRebasesAnchorAndPreservesGroupsAndThirdDisplay() async throws {
        let rectangles = [Rect(topLeftX: 0, topLeftY: 0, width: 1200, height: 800),
                          Rect(topLeftX: 1200, topLeftY: 0, width: 2400, height: 1400),
                          Rect(topLeftX: 3600, topLeftY: 200, width: 1600, height: 1000)]
        let displays = rectangles.enumerated().map { index, rect in
            TestMonitor(monitorAppKitNsScreenScreensId: index + 1, name: "Move-\(index)", rect: rect,
                        visibleRect: rect, isMain: index == 0)
        }
        setMonitorsForTests(displays)
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        TestWindow.new(id: 98301, parent: tabs)
        TestWindow.new(id: 98302, parent: tabs)
        TestWindow.new(id: 98303, parent: root)
        let selected = TestWindow.new(id: 98304, parent: root)
        let floating = TestWindow.new(id: 98305, parent: workspace)
        let other = Workspace.get(byName: "destination")
        TestWindow.new(id: 98306, parent: other.rootTilingContainer)
        let third = Workspace.get(byName: "unaffected")
        TestWindow.new(id: 98307, parent: third.rootTilingContainer)
        XCTAssertTrue(displays[0].setActiveWorkspace(workspace))
        XCTAssertTrue(displays[1].setActiveWorkspace(other))
        XCTAssertTrue(displays[2].setActiveWorkspace(third))
        workspace.transitionArrangement(to: .scrolling)
        workspace.workspaceLayoutUnits.forEach { $0.scrollingColumnWidth = 0.7 }
        _ = selected.focusWindow()
        try await workspace.layoutWorkspace()
        let originalProject = workspace.projectId
        let originalID = workspace.id
        let originalGroups = root.children
        let originalOffset = workspace.scrollingOffset
        let anchorPosition = try XCTUnwrap(workspace.scrollingAnchorViewportPosition)
        XCTAssertTrue(other.focusWorkspace())
        XCTAssertTrue(workspace.focusWorkspace())
        XCTAssertEqual(workspace.assignedMonitor?.rect.topLeftCorner, displays[0].rect.topLeftCorner)
        XCTAssertTrue(displays[1].activeWorkspace === other)

        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(workspace, targetMonitor: displays[1]))
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.assignedMonitor?.rect.topLeftCorner, displays[1].rect.topLeftCorner)
        XCTAssertTrue(displays[1].activeWorkspace === workspace)
        XCTAssertFalse(displays[0].activeWorkspace === workspace)
        XCTAssertTrue(displays[2].activeWorkspace === third)
        let metrics = workspace.scrollingMetrics
        let column = try XCTUnwrap(metrics.columns.first { $0.node === selected })
        XCTAssertEqual(workspace.scrollingOffset,
                       metrics.clampedOffset(column.start + column.width / 2 - anchorPosition * metrics.areaWidth), accuracy: 1)
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(workspace, targetMonitor: displays[0]))
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.scrollingOffset, originalOffset, accuracy: 1)
        XCTAssertEqual(workspace.id, originalID)
        XCTAssertEqual(workspace.projectId, originalProject)
        XCTAssertTrue(workspace.rootTilingContainer === root)
        XCTAssertEqual(root.children, originalGroups)
        XCTAssertEqual(tabs.layout, .tabGroup)
        XCTAssertEqual(tabs.children.count, 2)
        XCTAssertTrue(floating.parent === workspace)
        XCTAssertTrue(displays[2].activeWorkspace === third)
    }

    func testGenericColumnLayoutKeepsWidthAndPresetsDoNotSkipCloseValues() async throws {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 98401, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 98402, parent: workspace.rootTilingContainer)
        workspace.transitionArrangement(to: .scrolling)
        first.scrollingColumnWidth = 0.49
        _ = first.focusWindow()
        try await run("layout tab-group")
        let group = try XCTUnwrap(first.parent as? TilingContainer)
        XCTAssertFalse(group === workspace.rootTilingContainer)
        XCTAssertEqual(group.layout, .tabGroup)
        XCTAssertEqual(group.scrollingColumnWidth, 0.49)
        XCTAssertTrue(workspace.workspaceLayoutUnits.contains(where: { $0 === second }))
        config.scrolling.widthPresets = [0.49, 0.49005, 0.75]
        try await run("scrolling-width next")
        XCTAssertEqual(group.scrollingColumnWidth, 0.49005)
        try await run("scrolling-width previous")
        XCTAssertEqual(group.scrollingColumnWidth, 0.49)
        try await run("scrolling-width previous")
        XCTAssertEqual(group.scrollingColumnWidth, 0.75)
        try await run("balance-sizes")
        XCTAssertNil(group.scrollingColumnWidth)
        XCTAssertEqual(group.layout, .tabGroup)
    }

    func testConfigurationRejectsInvalidWidthsAndAcceptsAnyFinitePositiveSensitivity() {
        for value in ["nan", "inf", "0", "-1"] {
            XCTAssertFalse(parseConfig("[scrolling]\ngesture-sensitivity = \(value)").errors.isEmpty)
        }
        XCTAssertTrue(parseConfig("[scrolling]\ngesture-sensitivity = 12.5").errors.isEmpty)
        for presets in ["[]", "[0.5, 0.25]", "[0.5, 0.5]", "[0.09, 0.5]"] {
            XCTAssertFalse(parseConfig("[scrolling]\nwidth-presets = \(presets)").errors.isEmpty)
        }
    }
}
