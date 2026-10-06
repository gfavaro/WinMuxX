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

    func testLegacySpiralMigratesWithoutResettingFrames() {
        bounds = Rect(topLeftX: 0, topLeftY: 0, width: 1600, height: 900)
        let root = focus.workspace.rootTilingContainer
        root.dwindleChildRatios = nil
        root.dwindleOrientation = nil
        for id: UInt32 in 1...4 { _ = TestWindow.new(id: id, parent: root) }
        let before = render()
        focus.workspace.normalizeContainers()
        XCTAssertTrue(root.isExplicitDwindle)
        XCTAssertEqual(render(), before)
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
        XCTAssertTrue(focus.workspace.rootTilingContainer.isExplicitDwindle)
        XCTAssertEqual(render(), before)
    }
}
