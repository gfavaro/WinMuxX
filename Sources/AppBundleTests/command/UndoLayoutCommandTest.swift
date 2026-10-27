@testable import AppBundle
import Common
import XCTest

@MainActor
final class UndoLayoutCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func run(_ text: String) async throws -> CmdResult {
        try await XCTUnwrap(parseCommand(text).unwrap().0).run(.defaultEnv, .emptyStdin)
    }

    func testUndoPutsBackEachLayoutChangeInTurn() async throws {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        _ = try await run("move right")
        _ = try await run("layout floating")
        XCTAssertTrue(Window.get(byId: 1)?.parent is Workspace)

        let first = try await run("undo-layout")
        XCTAssertEqual(first.exitCode, 0)
        XCTAssertEqual(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(2), .window(1), .window(3)]), "Tiled again where it was")
        let second = try await run("undo-layout")
        XCTAssertEqual(second.exitCode, 0)
        XCTAssertEqual(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
        let result = try await run("undo-layout")
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, ["Nothing to undo on this workspace"])
    }

    func testCommandsThatChangeNothingAreNotRecorded() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        _ = try await run("balance-sizes") // Already balanced.
        let result = try await run("undo-layout")
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testWindowsThatArrivedOrLeftSinceAreRespected() async throws {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        _ = try await run("move right")
        Window.get(byId: 3)?.unbindFromParent() // Closed since.
        TestWindow.new(id: 4, parent: workspace.rootTilingContainer) // Opened since.
        let result = try await run("undo-layout")
        XCTAssertEqual(result.exitCode, 0)
        let ids = workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId)
        XCTAssertEqual(Array(ids.prefix(2)), [1, 2], "The recorded order is back")
        XCTAssertTrue(ids.contains(4), "The newer window stays tiled")
        XCTAssertFalse(ids.contains(3), "A window no longer here is not pulled back")
    }
}
