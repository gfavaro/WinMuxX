@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WorkspaceArrangementRegressionTest: WorkspaceTestCase {
    private func run(_ text: String) async throws -> CmdResult {
        try await XCTUnwrap(parseCommand(text).cmdOrNil).run(.defaultEnv, .emptyStdin)
    }

    func testDirectionalFocusUsesScrollingArrangement() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        root.changeOrientation(.v)
        let a = TestWindow.new(id: 94601, parent: root)
        let b = TestWindow.new(id: 94602, parent: root)
        for mode in [WorkspaceLayoutName.scrolling, .master] {
            workspace.arrangement = mode
            _ = a.focusWindow()
            try await workspace.layoutWorkspace()
            XCTAssertLessThan(try XCTUnwrap(a.lastAppliedLayoutPhysicalRect).minX,
                              try XCTUnwrap(b.lastAppliedLayoutPhysicalRect).minX)
            XCTAssertTrue(dwindleDirectionalFocusTarget(from: a, direction: .right) === b,
                          "\(mode): \(dwindleFocusFrames(in: workspace))")
            let result = try await run("focus right --boundaries workspace")
            XCTAssertEqual(result.exitCode, 0, result.stderr.joined())
            XCTAssertTrue(focus.windowOrNil === b, "The pane on the right should receive focus in \(mode)")
        }
    }

    func testMasterPaneCanStillBeResized() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        root.changeOrientation(.h)
        let a = TestWindow.new(id: 94611, parent: root)
        TestWindow.new(id: 94612, parent: root)
        workspace.arrangement = .master
        _ = a.focusWindow()
        try await workspace.layoutWorkspace()
        let before = try XCTUnwrap(a.lastAppliedLayoutPhysicalRect).width
        _ = try await run("resize width +100")
        try await workspace.layoutWorkspace()
        XCTAssertGreaterThan(try XCTUnwrap(a.lastAppliedLayoutPhysicalRect).width, before)
    }

    func testMasterPanesAndNavigationFollowAllFourSides() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let primary = TestWindow.new(id: 94615, parent: root)
        let other = TestWindow.new(id: 94616, parent: root)
        workspace.arrangement = .master
        workspace.masterRatio = 0.7
        for (side, direction): (MasterSide, CardinalDirection) in [(.left, .right), (.right, .left), (.top, .down), (.bottom, .up)] {
            config.master.side = side
            _ = primary.focusWindow()
            try await workspace.layoutWorkspace()
            let available = workspaceTilingRect(workspace)
            for window in [primary, other] {
                let frame = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
                XCTAssertGreaterThanOrEqual(frame.minX, available.minX)
                XCTAssertGreaterThanOrEqual(frame.minY, available.minY)
                XCTAssertLessThanOrEqual(frame.maxX, available.maxX + 0.01)
                XCTAssertLessThanOrEqual(frame.maxY, available.maxY + 0.01)
            }
            XCTAssertTrue(dwindleDirectionalFocusTarget(from: primary, direction: direction) === other)
        }
    }

    func testNewGroupDoesNotChangeExistingMaster() throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let a = TestWindow.new(id: 94621, parent: root)
        TestWindow.new(id: 94622, parent: root)
        let originalMaster = TestWindow.new(id: 94623, parent: root)
        workspace.arrangement = .master
        workspace.masterGroupIndex = 2
        _ = a.focusWindow()
        let binding = bindingDataForNewTilingWindow(workspace, window: nil)
        let inserted = TestWindow.new(id: 94624, parent: workspace)
        inserted.unbindFromParent()
        inserted.bind(to: binding.parent, adaptiveWeight: 1, index: binding.index)
        workspace.normalizeMasterLayout()
        XCTAssertTrue(workspace.workspaceLayoutUnits[workspace.masterGroupIndex] === originalMaster)
        a.unbindFromParent()
        workspace.normalizeMasterLayout()
        XCTAssertTrue(workspace.workspaceLayoutUnits[workspace.masterGroupIndex] === originalMaster)
    }

    func testCenterCommandClampsEndpointColumnsToStripBounds() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let a = TestWindow.new(id: 94631, parent: root)
        TestWindow.new(id: 94632, parent: root)
        let last = TestWindow.new(id: 94633, parent: root)
        workspace.arrangement = .scrolling
        for window in [a, last] {
            _ = window.focusWindow()
            let result = try await run("scrolling-center")
            XCTAssertEqual(result.exitCode, 0)
            try await workspace.layoutWorkspace()
            let metrics = workspace.scrollingMetrics
            let column = try XCTUnwrap(metrics.columns.first(where: { $0.node === window }))
            XCTAssertEqual(workspace.scrollingOffset, metrics.clampedOffset(column.start + column.width / 2 - metrics.areaWidth / 2), accuracy: 1)
        }
    }

    func testPureScrollingGeometryCentersFittingStripAndClampsOverflowEnds() throws {
        let fitting = calculateScrollingWorkspaceGeometry(.init(
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 700), parkingBounds: CGRect(x: 0, y: 0, width: 1000, height: 700), offset: 500,
            columns: [.init(preferredWidth: 0.3, minimumWidth: 0), .init(preferredWidth: 0.3, minimumWidth: 0)],
            horizontalGap: 20, outerLeft: 0, outerRight: 0, leftWall: false, rightWall: false, preview: 25))
        XCTAssertEqual(fitting.clampedOffset, -186, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(fitting.columns.first).logicalFrame.minX, 221, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(fitting.columns.last).logicalFrame.maxX, 779, accuracy: 1)

        let overflow = calculateScrollingWorkspaceGeometry(.init(
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 700), parkingBounds: CGRect(x: 0, y: 0, width: 1000, height: 700), offset: 9999,
            columns: Array(repeating: .init(preferredWidth: 0.7, minimumWidth: 0), count: 4),
            horizontalGap: 20, outerLeft: 0, outerRight: 0, leftWall: false, rightWall: false, preview: 25))
        XCTAssertEqual(overflow.clampedOffset, 1674, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(overflow.columns.first).physicalFrame.maxX, 25, accuracy: 1)
        XCTAssertEqual(overflow.columns.count, overflow.stackingOrder.count)
        XCTAssertEqual(overflow.columns.count, 4)
    }

    func testAnOpenSheetStretchesTheScrollRangePastTheStripStart() throws {
        func geometry(offset: CGFloat, sheet: CGFloat?) -> ScrollingWorkspaceGeometry {
            calculateScrollingWorkspaceGeometry(.init(
                bounds: CGRect(x: 0, y: 0, width: 1000, height: 700), parkingBounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
                offset: offset, columns: Array(repeating: .init(preferredWidth: 0.7, minimumWidth: 0), count: 3),
                horizontalGap: 20, outerLeft: 0, outerRight: 0, leftWall: false, rightWall: false, preview: 25, sheetOffset: sheet))
        }
        // Without a sheet the strip stops at its first column.
        XCTAssertEqual(geometry(offset: -180, sheet: nil).clampedOffset, 0)
        // A sheet sticking out left of the first column moves the whole strip right.
        let open = geometry(offset: -180, sheet: -180)
        XCTAssertEqual(open.clampedOffset, -180)
        XCTAssertEqual(open.offsetRange.lowerBound, -180)
        XCTAssertGreaterThan(try XCTUnwrap(open.columns.first).logicalFrame.minX, 150, "Room left of the first column for the sheet")
        // Past the last column too.
        let end = geometry(offset: 0, sheet: 0).offsetRange.upperBound
        XCTAssertEqual(geometry(offset: end + 120, sheet: end + 120).clampedOffset, end + 120, accuracy: 0.5)
    }

    func testSheetRevealIsNotCappedAtTheStripEnds() throws {
        let workspace = focus.workspace
        workspace.arrangement = .scrolling
        (0..<3).forEach { _ = TestWindow.new(id: UInt32(97300 + $0), parent: workspace.rootTilingContainer) }
        let metrics = workspace.scrollingMetrics
        let lower = metrics.offsetRange.lowerBound
        XCTAssertEqual(metrics.sheetRevealedOffset(start: lower - 150, end: lower + 300, current: lower), lower - 150)
        XCTAssertEqual(metrics.revealedOffset(start: lower - 150, end: lower + 300, current: lower), lower, "The ordinary reveal stays capped")
    }

    func testPureScrollingGeometryContainsParkedColumnsAtAdjacentDisplayWalls() {
        let geometry = calculateScrollingWorkspaceGeometry(.init(
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 700), parkingBounds: CGRect(x: 0, y: 0, width: 1000, height: 700), offset: 800,
            columns: [.init(preferredWidth: 0.6, minimumWidth: 0), .init(preferredWidth: 0.6, minimumWidth: 0)],
            horizontalGap: 16, outerLeft: 0, outerRight: 0, leftWall: true, rightWall: true, preview: 25))
        XCTAssertGreaterThanOrEqual(geometry.columns[0].physicalFrame.minX, 0)
        XCTAssertLessThanOrEqual(geometry.columns[0].physicalFrame.maxX, 1000)
        XCTAssertGreaterThanOrEqual(geometry.columns[1].physicalFrame.minX, 0)
        XCTAssertLessThanOrEqual(geometry.columns[1].physicalFrame.maxX, 1000)
    }

    func testFocusedOversizedMinimumUsesCenteredBestEffortWithinMonitor() {
        let geometry = calculateScrollingWorkspaceGeometry(.init(
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            parkingBounds: CGRect(x: 100, y: 0, width: 800, height: 700), offset: 1000,
            columns: [.init(preferredWidth: 0.49, minimumWidth: 1200)], horizontalGap: 16,
            outerLeft: 0, outerRight: 0, leftWall: true, rightWall: true, preview: 25,
            focusedColumnIndex: 0))
        XCTAssertEqual(geometry.columns[0].physicalFrame.midX, 500, accuracy: 1)
        XCTAssertGreaterThan(geometry.columns[0].physicalFrame.width, geometry.area.width)
    }

    func testRefreshNormalizationPreservesScrollingGroups() throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        root.dwindleOrientation = .h
        root.dwindleChildRatios = [0.5, 0.5]
        let split = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 0)
        TestWindow.new(id: 94641, parent: split)
        TestWindow.new(id: 94642, parent: split)
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tabGroup, index: 1)
        TestWindow.new(id: 94643, parent: tabs)
        TestWindow.new(id: 94644, parent: tabs)
        let splitChildren = split.children
        let tabChildren = tabs.children
        for mode in [WorkspaceLayoutName.master, .scrolling, .dwindle] {
            workspace.arrangement = mode
            workspace.normalizeContainers()
            XCTAssertTrue(workspace.rootTilingContainer === root)
            XCTAssertEqual(workspace.rootTilingContainer.children, [split, tabs])
            XCTAssertEqual(split.layout, .tiles)
            XCTAssertEqual(split.children, splitChildren)
            XCTAssertEqual(tabs.layout, .tabGroup)
            XCTAssertEqual(tabs.children, tabChildren)
        }
    }

    func testMoveExtractsFocusedWindowFromSharedGroupAtEitherStripEdge() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let shared = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: 0)
        let first = TestWindow.new(id: 94671, parent: shared)
        let retained = TestWindow.new(id: 94672, parent: shared)
        let neighbor = TestWindow.new(id: 94673, parent: root)
        workspace.arrangement = .scrolling

        XCTAssertTrue(first.focusWindow())
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .left)).run(.defaultEnv, .emptyStdin)
        XCTAssertTrue(shared.children.contains(where: { $0 === retained }))
        XCTAssertFalse(shared.children.contains(where: { $0 === first }))
        XCTAssertTrue(root.children.first === first, "A shared edge column can extract a new column at the strip start")

        // Put a shared column at the opposite edge and extract a second window.
        shared.unbindFromParent()
        shared.bind(to: root, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        let last = TestWindow.new(id: 94674, parent: shared)
        XCTAssertTrue(last.focusWindow())
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .right)).run(.defaultEnv, .emptyStdin)
        XCTAssertFalse(shared.children.contains(where: { $0 === last }))
        XCTAssertTrue(root.children.last === last)
        XCTAssertTrue(root.children.contains(where: { $0 === neighbor }))
        XCTAssertEqual(workspace.workspaceLayoutUnits.count, 4)
    }

    func testMoveSwapsSingletonColumnsAndKeepsVerticalMovesInsideGroup() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let left = TestWindow.new(id: 94681, parent: root)
        let right = TestWindow.new(id: 94682, parent: root)
        workspace.arrangement = .scrolling
        XCTAssertTrue(left.focusWindow())
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .right)).run(.defaultEnv, .emptyStdin)
        XCTAssertTrue(root.children.first === right)
        XCTAssertTrue(root.children.last === left)

        let column = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 2)
        let nested = TilingContainer(parent: column, adaptiveWeight: 1, .v, .tiles, index: 0)
        let upper = TestWindow.new(id: 94683, parent: nested)
        let lower = TestWindow.new(id: 94684, parent: nested)
        workspace.arrangement = .scrolling
        XCTAssertTrue(upper.focusWindow())
        try await MoveCommand(args: MoveCmdArgs(rawArgs: [], .down)).run(.defaultEnv, .emptyStdin)
        XCTAssertTrue(nested.children.first === lower)
        XCTAssertTrue(nested.children.last === upper)
        XCTAssertTrue(root.children.contains(where: { $0 === column }), "Vertical move stays in its nested column")
    }

    func testHorizontalJoinAdoptsNeighborWidthAndCreatesNestedGroup() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let source = TestWindow.new(id: 94691, parent: root)
        let target = TestWindow.new(id: 94692, parent: root)
        source.scrollingColumnWidth = 0.4
        target.scrollingColumnWidth = 0.72
        workspace.arrangement = .scrolling
        XCTAssertTrue(source.focusWindow())
        let result = try await JoinWithCommand(args: JoinWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined())
        let joined = try XCTUnwrap(workspace.workspaceLayoutUnits.first as? TilingContainer)
        XCTAssertEqual(joined.scrollingColumnWidth ?? 0, 0.72, accuracy: 0.001)
        XCTAssertEqual(Set(joined.allLeafWindowsRecursive.map(\.windowId)), [source.windowId, target.windowId])
    }

    func testMasterRatioAndGroupProtectionSurviveRestartInDwindleMode() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        root.dwindleOrientation = .h
        root.dwindleChildRatios = [0.5, 0.5]
        let primary = TestWindow.new(id: 94651, parent: root)
        let split = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tiles, index: 1)
        let b = TestWindow.new(id: 94652, parent: split)
        let c = TestWindow.new(id: 94653, parent: split)
        workspace.arrangement = .master
        _ = primary.focusWindow()
        try await workspace.layoutWorkspace()
        _ = try await run("resize width +100")
        let ratio = try XCTUnwrap(workspace.masterRatio)
        workspace.arrangement = .dwindle
        let frozen = try JSONDecoder().decode(FrozenWorkspace.self, from: JSONEncoder().encode(FrozenWorkspace(workspace)))
        let restored = try await restoreFrozenWorldIfNeeded(
            FrozenWorld(workspaces: [frozen], monitors: [], windowIds: Set([primary, b, c].map(\.windowId))),
            newlyDetectedWindow: primary, restoreVisibleWorkspaces: false)
        XCTAssertTrue(restored)
        XCTAssertEqual(workspace.arrangement, .dwindle)
        XCTAssertEqual(workspace.masterRatio, ratio)
        XCTAssertTrue(workspace.preservesTopLevelGroups)
        workspace.normalizeContainers()
        XCTAssertEqual(workspace.rootTilingContainer.children.count, 2)
        let restoredSplit = try XCTUnwrap(workspace.rootTilingContainer.children.last as? TilingContainer)
        XCTAssertEqual(restoredSplit.layout, .tiles)
        XCTAssertEqual(restoredSplit.children, [b, c])
    }

    func testMinimapUsesTheWorkspaceDisplayIncludingNegativeCoordinates() throws {
        let main = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let external = CGRect(x: -908, y: 1112, width: 3440, height: 1440)
        let panel = try XCTUnwrap(scrollingMinimapFrame(size: CGSize(width: 300, height: 70),
            visibleFrames: [main, external], screenIndex: 2))
        XCTAssertEqual(panel.midX, external.midX)
        XCTAssertEqual(panel.minY, external.minY + 32)
        XCTAssertTrue(external.contains(panel))
        XCTAssertNil(scrollingMinimapFrame(size: .zero, visibleFrames: [main], screenIndex: 2))
    }
}
