@testable import AppBundle
import Common
import XCTest

/// Workspaces that have used Master, Tabbed or Scrolling keep their group boundaries, but no
/// one-child wrappers: those used to pile up there.
@MainActor
final class NormalizeContainersArrangedTest: WorkspaceTestCase {
    private func run(_ text: String) async throws {
        let result = try await XCTUnwrap(parseCommand(text).cmdOrDie).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0, text)
    }

    func testAOneChildWrapperGivesItsPlaceShareAndWidthsToItsChild() {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        workspace.arrangement = .scrolling
        let left = TestWindow.new(id: 77000, parent: root, adaptiveWeight: 1)
        let outer = TilingContainer(parent: root, adaptiveWeight: 3, .v, .tiles, index: INDEX_BIND_LAST)
        outer.scrollingColumnWidth = 0.7
        outer.stripColumnWidth = 0.4
        let inner = TilingContainer(parent: outer, adaptiveWeight: 1, .v, .tiles, index: 0)
        let wrapped = TestWindow.new(id: 77001, parent: inner)
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tabGroup, index: INDEX_BIND_LAST)
        let tab = TestWindow.new(id: 77002, parent: tabs)
        workspace.normalizeContainers()
        XCTAssertEqual(root.children.count, 3)
        XCTAssertTrue(root.children[0] === left)
        XCTAssertTrue(root.children[1] === wrapped, "The window takes the wrappers' place")
        XCTAssertEqual(wrapped.getWeight(root.orientation), 3, "and their share")
        XCTAssertEqual(wrapped.scrollingColumnWidth, 0.7)
        XCTAssertEqual(wrapped.stripColumnWidth, 0.4)
        XCTAssertTrue(tab.parent === tabs, "A tab group of one tab stays a tab group")
        XCTAssertTrue(root.parent === workspace)
    }

    func testAChildsOwnWidthWins() {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        workspace.arrangement = .master
        _ = TestWindow.new(id: 77010, parent: root)
        let wrapper = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: INDEX_BIND_LAST)
        wrapper.scrollingColumnWidth = 0.7
        let window = TestWindow.new(id: 77011, parent: wrapper)
        window.scrollingColumnWidth = 0.4
        workspace.normalizeContainers()
        XCTAssertEqual(window.scrollingColumnWidth, 0.4)
    }

    func testRoundTripsThroughEveryLayoutKeepTheDwindleFrames() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        root.dwindleOrientation = .h
        let a = TestWindow.new(id: 77020, parent: root)
        let right = TilingContainer(parent: root, adaptiveWeight: 1, .v, .dwindle, index: INDEX_BIND_LAST)
        right.dwindleOrientation = .v
        let wrapper = TilingContainer(parent: right, adaptiveWeight: 1, .h, .tiles, index: 0)
        let b = TestWindow.new(id: 77021, parent: wrapper)
        let c = TestWindow.new(id: 77022, parent: right)
        _ = a.focusWindow()
        try await workspace.layoutWorkspace()
        let windows = [a, b, c]
        let before = windows.map(\.lastAppliedLayoutPhysicalRect)
        for layout in ["master", "tabbed", "scrolling"] {
            try await run("workspace-layout \(layout)")
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
            try await run("workspace-layout dwindle")
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
            XCTAssertEqual(windows.map(\.lastAppliedLayoutPhysicalRect), before, "after \(layout)")
        }
    }
}
