@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WorkspaceLayoutCommandTest: WorkspaceTestCase {
    private func run(_ text: String, env: CmdEnv = .defaultEnv) async throws -> CmdResult {
        try await XCTUnwrap(parseCommand(text).cmdOrNil).run(env, .emptyStdin)
    }

    func testLayoutCyclesThroughAllThreeContainerModes() async throws {
        let root = focus.workspace.rootTilingContainer
        root.layout = .tiles
        let window = TestWindow.new(id: 28001, parent: root)
        TestWindow.new(id: 28002, parent: root)
        _ = window.focusWindow()
        for expected: Layout in [.stacked, .tabGroup, .tiles] {
            let result = try await parseCommand("layout tiles accordion tab-group").cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertEqual(focus.workspace.rootTilingContainer.layout, expected)
            XCTAssertTrue(focus.windowOrNil === window)
        }
    }

    func testWorkspaceAndContainerCommandsHaveSeparateParsers() {
        for command in ["layout master", "layout dwindle", "layout tiles master", "layout scrolling",
                        "workspace-layout tiles", "workspace-layout accordion", "workspace-layout scrolling", "workspace-layout"] {
            XCTAssertNotNil(parseCommand(command).errorOrNil, command)
        }
        for command in ["workspace-layout master", "workspace-layout dwindle master", "layout tiles accordion"] {
            XCTAssertNil(parseCommand(command).errorOrNil, command)
        }
        let old = parseConfig("[mode.main.binding]\nalt-space = 'layout dwindle'")
        XCTAssertFalse(old.errors.isEmpty)
        let migrated = parseConfig("[mode.main.binding]\nalt-space = 'workspace-layout dwindle'")
        XCTAssertTrue(migrated.errors.isEmpty, "\(migrated.errors)")
    }

    func testContainerCycleAdvancesAfterLastMatchingDescription() async throws {
        let root = focus.workspace.rootTilingContainer
        root.layout = .tiles
        root.changeOrientation(.h)
        let first = TestWindow.new(id: 28010, parent: root)
        TestWindow.new(id: 28011, parent: root)
        _ = first.focusWindow()
        let result = try await run("layout tiles horizontal vertical")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(root.orientation, .v)
        XCTAssertEqual(root.layout, .tiles)
    }

    func testWorkspaceSwitchTargetsRootAndPreservesOtherWorkspaceAndTabGroups() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let first = TestWindow.new(id: 28100, parent: root)
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tabGroup, index: INDEX_BIND_LAST)
        let tab = TestWindow.new(id: 28101, parent: tabs)
        let otherTab = TestWindow.new(id: 28102, parent: tabs)
        let other = Workspace.get(byName: "other")
        other.rootTilingContainer.layout = .stacked
        let unrelated = TestWindow.new(id: 28103, parent: other.rootTilingContainer)
        _ = unrelated.focusWindow()
        let result = try await run("workspace-layout --window-id \(tab.windowId) master")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(workspace.rootTilingContainer.layout, .master)
        XCTAssertTrue(workspace.rootTilingContainer.children.first === tabs)
        XCTAssertEqual(tabs.children, [tab, otherTab])
        XCTAssertEqual(other.rootTilingContainer.layout, .stacked)
        XCTAssertEqual(other.rootTilingContainer.children, [unrelated])
        XCTAssertTrue(focus.windowOrNil === unrelated)
        let exit = try await run("workspace-layout --window-id \(first.windowId) dwindle")
        XCTAssertEqual(exit.exitCode, 0)
        XCTAssertEqual(workspace.layoutName, "dwindle")
        XCTAssertEqual(tabs.children, [tab, otherTab])
        XCTAssertTrue(focus.windowOrNil === unrelated)
    }

    func testWorkspaceTogglePreservesManualAccordionStackOnExit() async throws {
        let root = focus.workspace.rootTilingContainer
        root.layout = .tiles
        let windows = (0..<3).map { TestWindow.new(id: UInt32(28200 + $0), parent: root) }
        _ = windows[0].focusWindow()
        let enter = try await run("workspace-layout dwindle master")
        XCTAssertEqual(enter.exitCode, 0)
        let change = try await run("layout accordion")
        XCTAssertEqual(change.exitCode, 0)
        let stack = try XCTUnwrap(focus.workspace.rootTilingContainer.children.compactMap { $0 as? TilingContainer }.first)
        XCTAssertEqual(stack.layout, .stacked)
        config.master.stackLayout = .tiles
        let exit = try await run("workspace-layout dwindle master")
        XCTAssertEqual(exit.exitCode, 0)
        XCTAssertEqual(focus.workspace.layoutName, "dwindle")
        XCTAssertEqual(stack.layout, .stacked)
        XCTAssertEqual(stack.children, Array(windows.dropFirst()))
        XCTAssertFalse(stack.isMasterStack)
        XCTAssertTrue(focus.windowOrNil === windows[0])
    }

    func testWorkspaceSwitchPreservesRootTabGroup() async throws {
        let root = focus.workspace.rootTilingContainer
        root.layout = .tabGroup
        let first = TestWindow.new(id: 28300, parent: root)
        let second = TestWindow.new(id: 28301, parent: root)
        _ = first.focusWindow()
        let result = try await run("workspace-layout dwindle")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.layoutName, "dwindle")
        XCTAssertEqual(root.layout, .tabGroup)
        XCTAssertEqual(root.children, [first, second])
        XCTAssertTrue(focus.windowOrNil === first)
    }

    func testEmptyFloatingAndInvalidTargetsDoNotChangeWorkspaceLayout() async throws {
        let root = focus.workspace.rootTilingContainer
        root.layout = .tiles
        let empty = try await run("workspace-layout master")
        XCTAssertNotEqual(empty.exitCode, 0)
        let floating = TestWindow.new(id: 28400, parent: focus.workspace)
        let floatResult = try await run("workspace-layout --window-id \(floating.windowId) master")
        XCTAssertNotEqual(floatResult.exitCode, 0)
        let invalid = try await run("workspace-layout --window-id 999999 master")
        XCTAssertNotEqual(invalid.exitCode, 0)
        XCTAssertEqual(root.layout, .tiles)
        XCTAssertTrue(floating.isFloating)
    }

    func testWorkspaceLayoutFormatIsSeparateFromContainerLayoutAndWorksInJSON() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let window = TestWindow.new(id: 28500, parent: root)
        _ = window.focusWindow()
        for (layout, expected): (Layout, String) in [(.tiles, "fixed"), (.stacked, "fixed"),
                                                    (.tabGroup, "fixed"), (.dwindle, "dwindle"), (.master, "master")] {
            root.layout = layout
            let values = [FormatObject.workspace(workspace)].format([.interVar("workspace-layout")])
            XCTAssertEqual(try values.get(), [expected])
            let output = try await run("list-windows --all --format %{workspace-layout} --json")
            XCTAssertEqual(output.exitCode, 0)
            let json = try JSONSerialization.jsonObject(with: Data(output.stdout.joined().utf8)) as? [[String: String]]
            XCTAssertEqual(json?.first?["workspace-layout"], expected)
        }
    }
}
