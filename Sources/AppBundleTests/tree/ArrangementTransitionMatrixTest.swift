@testable import AppBundle
import Common
import XCTest

/// Every ordered pair of workspace arrangements, there and back: switching presentation keeps
/// the workspace's windows, its tab group, focus and a healthy model (INV-005).
@MainActor
final class ArrangementTransitionMatrixTest: WorkspaceTestCase {
    private let arrangements = ["dwindle", "master", "tabbed", "scrolling"]

    private func run(_ text: String) async throws {
        let result = try await XCTUnwrap(parseCommand(text).cmdOrDie).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0, text)
    }

    private func switchTo(_ layout: String, _ workspace: Workspace) async throws {
        try await run("workspace-layout \(layout)")
        XCTAssertEqual(workspace.arrangement.rawValue, layout)
        workspace.normalizeContainers()
        try await workspace.layoutWorkspace()
    }

    func testEveryPairOfArrangementsKeepsWindowsGroupsAndFocus() async throws {
        for from in arrangements {
            for to in arrangements where to != from {
                try await assertRoundTrip(from: from, to: to)
            }
        }
    }

    private func assertRoundTrip(from: String, to: String) async throws {
        setUpWorkspacesForTests()
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let a = TestWindow.new(id: 78000, parent: root)
        let right = TilingContainer(parent: root, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        let wrapper = TilingContainer(parent: right, adaptiveWeight: 1, .h, .tiles, index: 0)
        let b = TestWindow.new(id: 78001, parent: wrapper)
        let tabs = TilingContainer(parent: right, adaptiveWeight: 1, .h, .tabGroup, index: INDEX_BIND_LAST)
        let t1 = TestWindow.new(id: 78002, parent: tabs)
        let t2 = TestWindow.new(id: 78003, parent: tabs)
        let floating = TestWindow.new(id: 78004, parent: workspace)
        let minimized = TestWindow.new(id: 78005, parent: macosMinimizedWindowsContainer)
        let all = [a, b, t1, t2, floating, minimized]
        _ = b.focusWindow()
        try await switchTo(from, workspace)

        let members = Set(workspace.allLeafWindowsRecursive.map(\.windowId))
        let frames = [a, b, t1, t2].map(\.lastAppliedLayoutPhysicalRect)
        let label = "\(from) → \(to)"

        try await switchTo(to, workspace)
        assertHealthy(workspace, members: members, focused: b, tabs: [t1, t2], all: all, "\(label)")

        try await switchTo(from, workspace)
        assertHealthy(workspace, members: members, focused: b, tabs: [t1, t2], all: all, "\(label) → \(from)")
        if from == "dwindle" {
            XCTAssertEqual([a, b, t1, t2].map(\.lastAppliedLayoutPhysicalRect), frames, "\(label) → \(from): frames")
        }
    }

    private func assertHealthy(_ workspace: Workspace, members: Set<UInt32>, focused: Window, tabs: [Window], all: [Window], _ label: String) {
        let leaves = workspace.allLeafWindowsRecursive.map(\.windowId)
        XCTAssertEqual(leaves.count, Set(leaves).count, "\(label): duplicated window")
        XCTAssertEqual(Set(leaves), members, "\(label): membership")
        XCTAssertTrue(focus.windowOrNil === focused, "\(label): focus")
        let group = tabs.first?.parent as? TilingContainer
        XCTAssertEqual(group?.layout, .tabGroup, "\(label): tab group")
        XCTAssertTrue(group.map { $0.children.filterIsInstance(of: Window.self) == tabs } ?? false, "\(label): tab order")
        XCTAssertEqual(runtime.modelInvariantViolations(expectedWindows: all), [], "\(label): model")
    }
}
