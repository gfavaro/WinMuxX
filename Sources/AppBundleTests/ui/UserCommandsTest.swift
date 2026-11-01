@testable import AppBundle
import XCTest

@MainActor
final class UserCommandsTest: WorkspaceTestCase {
    func testUiWorkspaceSelectionRunsTheWorkspaceCommand() async throws {
        _ = Workspace.get(byName: "a").focusWorkspace()
        _ = TestWindow.new(id: 9901, parent: Workspace.get(byName: "b").rootTilingContainer)
        let error = try await selectWorkspaceFromUi("b")
        XCTAssertNil(error)
        XCTAssertEqual(focus.workspace.name, "b")
        let missing = try await selectWorkspaceFromUi("never-created")
        XCTAssertNil(missing)
        XCTAssertEqual(focus.workspace.name, "b")
    }
}
