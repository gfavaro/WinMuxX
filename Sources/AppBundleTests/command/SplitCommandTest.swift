@testable import AppBundle
import Common
import XCTest

@MainActor
final class SplitCommandTest: WorkspaceTestCase {

    func testSplitWrapsWindowForExplicitAndOppositeOrientation() async throws {
        for argument: SplitCmdArgs.SplitArg in [.vertical, .opposite] {
            setUpWorkspacesForTests()
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            try await SplitCommand(args: SplitCmdArgs(rawArgs: [], argument)).run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(root.layoutDescription, .h_tiles([
                .v_tiles([
                    .window(1),
                ]),
                .window(2),
            ]), argument.rawValue)
        }
    }

    func testSingleChildContainerChangesForExplicitAndOppositeOrientation() async throws {
        for argument: SplitCmdArgs.SplitArg in [.horizontal, .opposite] {
            setUpWorkspacesForTests()
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                }
                TestWindow.new(id: 2, parent: $0)
            }

            try await SplitCommand(args: SplitCmdArgs(rawArgs: [], argument)).run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(root.layoutDescription, .h_tiles([
                .h_tiles([
                    .window(1),
                ]),
                .window(2),
            ]), argument.rawValue)
        }
    }
}
