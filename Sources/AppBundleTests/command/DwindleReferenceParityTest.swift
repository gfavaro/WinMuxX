@testable import AppBundle
import AppKit
import Common
import XCTest

/// Golden frames obtained by running Dinky's actual DinkyLayout engine at
/// d488ce74eb1ec4319409118f56caebd88844fac6 (zero gaps, 1600-point canvas).
@MainActor
final class DwindleReferenceParityTest: XCTestCase {
    private var bounds = Rect(topLeftX: 0, topLeftY: 0, width: 1600, height: 400)

    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.gaps = .zero
        let root = focus.workspace.rootTilingContainer
        root.layout = .dwindle
        root.dwindleOrientation = .h
        root.dwindleChildRatios = []
    }

    @discardableResult
    private func render() -> [UInt32: Rect] {
        var result: [UInt32: Rect] = [:]
        let gaps = ResolvedGaps(gaps: .zero, monitor: focus.workspace.workspaceMonitor)
        func visit(_ node: TreeNode, _ rect: Rect) {
            node.lastAppliedLayoutPhysicalRect = rect
            if let window = node as? Window { result[window.windowId] = rect }
            if let container = node as? TilingContainer {
                for (child, frame) in zip(container.children, container.dwindleChildFrames(in: rect, gaps: gaps)) {
                    visit(child, frame)
                }
            }
        }
        visit(focus.workspace.rootTilingContainer, bounds)
        return result
    }

    private func insert(_ id: UInt32) -> TestWindow {
        let workspace = focus.workspace
        let binding = bindingDataForNewTilingWindow(workspace, window: nil)
        let window = TestWindow.new(id: id, parent: workspace)
        window.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
        _ = window.focusWindow()
        render()
        return window
    }

    private func assertFrames(_ expected: [UInt32: CGRect], file: StaticString = #filePath, line: UInt = #line) {
        let actual = render()
        XCTAssertEqual(Set(actual.keys), Set(expected.keys), file: file, line: line)
        for (id, frame) in expected {
            guard let got = actual[id] else { continue }
            for (a, b) in zip([got.minX, got.minY, got.width, got.height], [frame.minX, frame.minY, frame.width, frame.height]) {
                XCTAssertEqual(a, b, accuracy: 1, "Window \(id)", file: file, line: line)
            }
        }
    }

    func testSiblingResizeInsertAndRemoveMatchDinky() {
        let first = insert(1)
        let second = insert(2)
        let third = insert(3)
        assertFrames([1: CGRect(x: 0, y: 0, width: 533, height: 400),
                      2: CGRect(x: 533, y: 0, width: 534, height: 400),
                      3: CGRect(x: 1067, y: 0, width: 533, height: 400)])
        _ = first.focusWindow()
        XCTAssertTrue(first.dwindleResizeTargets().first!.resize(.add(100)))
        render()
        _ = third.focusWindow()
        _ = insert(4)
        assertFrames([1: CGRect(x: 0, y: 0, width: 475, height: 400),
                      2: CGRect(x: 475, y: 0, width: 363, height: 400),
                      3: CGRect(x: 838, y: 0, width: 362, height: 400),
                      4: CGRect(x: 1200, y: 0, width: 400, height: 400)])
        second.unbindFromParent()
        focus.workspace.normalizeContainers()
        assertFrames([1: CGRect(x: 0, y: 0, width: 614, height: 400),
                      3: CGRect(x: 614, y: 0, width: 469, height: 400),
                      4: CGRect(x: 1083, y: 0, width: 517, height: 400)])
    }

    func testPromotedRootKeepsDinkyAxisAndGeometry() {
        bounds = Rect(topLeftX: 0, topLeftY: 0, width: 1600, height: 900)
        let first = insert(1)
        _ = insert(2)
        _ = insert(3)
        _ = insert(4)
        assertFrames([1: CGRect(x: 0, y: 0, width: 800, height: 900),
                      2: CGRect(x: 800, y: 0, width: 800, height: 450),
                      3: CGRect(x: 800, y: 450, width: 400, height: 450),
                      4: CGRect(x: 1200, y: 450, width: 400, height: 450)])
        first.unbindFromParent()
        focus.workspace.normalizeContainers()
        XCTAssertEqual(focus.workspace.rootTilingContainer.dwindleOrientation, .v)
        assertFrames([2: CGRect(x: 0, y: 0, width: 1600, height: 450),
                      3: CGRect(x: 0, y: 450, width: 800, height: 450),
                      4: CGRect(x: 800, y: 450, width: 800, height: 450)])
    }

    func testMouseEdgeResizeTransfersOnlyToAdjacentSibling() {
        let first = insert(1)
        _ = insert(2)
        _ = insert(3)
        let edge = first.dwindleResizeTargets().first!
        edge.container.setDwindleSplitRatio(edge.ratio(forLength: edge.leadingLength + 100), at: edge.splitIndex)
        assertFrames([1: CGRect(x: 0, y: 0, width: 633, height: 400),
                      2: CGRect(x: 633, y: 0, width: 434, height: 400),
                      3: CGRect(x: 1067, y: 0, width: 533, height: 400)])
    }

    func testMouseResizeBoundsUseWholeContainerShares() {
        let first = insert(1)
        _ = insert(2)
        _ = insert(3)
        let edge = first.dwindleResizeTargets().first!
        edge.container.setDwindleSplitRatio(edge.ratio(forLength: 100000), at: edge.splitIndex)
        let shares = edge.container.dwindleShares(count: 3)
        XCTAssertEqual(shares[1], 0.1, accuracy: 0.000001)
        XCTAssertEqual(shares[2], 1.0 / 3, accuracy: 0.000001)
    }

    func testWindowsFoundTogetherSpiralBeforeAnyIsLaidOut() {
        bounds = Rect(topLeftX: 0, topLeftY: 0, width: 1600, height: 900)
        let workspace = focus.workspace
        workspace.rootTilingContainer.dwindleOrientation = nil
        // As at startup: each window is placed before the previous ones have frames.
        let windows: [TestWindow] = (1...4).map { id in
            let binding = bindingDataForNewTilingWindow(workspace, window: nil)
            let window = TestWindow.new(id: UInt32(id), parent: workspace)
            window.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
            return window
        }
        let frames = render()
        let rects = windows.map { frames[$0.windowId]! }
        XCTAssertLessThan(rects[0].maxX, rects[1].minX + 1, "The first window takes the left side")
        XCTAssertLessThan(rects[1].maxY, rects[2].minY + 1, "The next ones stack beneath")
        XCTAssertGreaterThan(rects.map(\.width).min()!, bounds.width / 5, "No window is squeezed into a column")
    }

    func testSpiralSavedByOlderVersionsRestoresWithTheSameFrames() async throws {
        bounds = Rect(topLeftX: 0, topLeftY: 0, width: 1600, height: 900)
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.dwindleOrientation = nil
        let windows = (1...4).map { TestWindow.new(id: UInt32($0), parent: root) }
        workspace.adoptDwindleSpiral(ratios: [0.6, 0.3])
        let before = render()
        // Older versions saved the same spiral as one list of windows with a ratio for each split.
        let data = try JSONEncoder().encode(snapshotCurrentFrozenWorld())
        var world = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var workspaces = try XCTUnwrap(world["workspaces"] as? [[String: Any]])
        let index = try XCTUnwrap(workspaces.firstIndex { $0["name"] as? String == workspace.name })
        var legacyRoot = try XCTUnwrap(workspaces[index]["rootTilingNode"] as? [String: Any])
        func windowNodes(_ node: [String: Any]) -> [[String: Any]] {
            (node["children"] as? [[String: Any]] ?? []).flatMap { child in
                child["kind"] as? String == "window" ? [child] : windowNodes(child["container"] as? [String: Any] ?? child)
            }
        }
        legacyRoot["children"] = windowNodes(legacyRoot)
        legacyRoot["dwindleSplitRatios"] = [0.6, 0.3]
        legacyRoot.removeValue(forKey: "dwindleChildRatios")
        legacyRoot.removeValue(forKey: "dwindleOrientation")
        workspaces[index]["rootTilingNode"] = legacyRoot
        world["workspaces"] = workspaces
        let legacy = try JSONDecoder().decode(FrozenWorld.self, from: JSONSerialization.data(withJSONObject: world))
        XCTAssertEqual(windowNodes(legacyRoot).count, windows.count)
        let restored = try await restoreFrozenWorldIfNeeded(legacy, newlyDetectedWindow: windows[0])
        XCTAssertTrue(restored)
        XCTAssertEqual(render(), before)
    }

    func testOldMasterTreeKeepsItsGroups() {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .master
        let main = TestWindow.new(id: 40, parent: root)
        let stack = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: INDEX_BIND_LAST)
        stack.isMasterStack = true
        let groups = (1...3).map { TestWindow.new(id: UInt32(40 + $0), parent: stack) }
        migrateLegacyMasterTree(workspace)
        XCTAssertEqual(root.children, [main] + groups, "Every group stays a top-level group")
        XCTAssertEqual(root.layout, .dwindle)
    }

    func testExplicitRatiosAndAxisSurviveSnapshotRestore() async throws {
        let first = insert(1)
        _ = insert(2)
        _ = insert(3)
        _ = first.focusWindow()
        _ = first.dwindleResizeTargets().first!.resize(.add(100))
        let before = render()
        let snapshot = snapshotCurrentFrozenWorld()
        let restored = try await restoreFrozenWorldIfNeeded(snapshot, newlyDetectedWindow: first)
        XCTAssertTrue(restored)
        XCTAssertEqual(render(), before)
    }
}
