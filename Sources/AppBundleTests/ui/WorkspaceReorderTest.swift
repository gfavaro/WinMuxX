@testable import AppBundle
import Common
import XCTest

/// Reordering workspaces within a project: numbers follow the new position, while windows,
/// project and identity stay put.
@MainActor
final class WorkspaceReorderTest: WorkspaceTestCase {
    private func makeWorkspaces(_ count: Int, restored: Bool = false) -> (WorkspaceProjectId, [Workspace]) {
        let project = createWorkspaceProject()
        let spaces = (0 ..< count).map { offset in
            let workspace = Workspace.get(byName: "reorder-\(offset)")
            workspace.assignProject(project.id)
            workspace.markAsAutomaticallyNamed()
            if restored { workspace.restoredDisplayIndex = count - offset }
            _ = TestWindow.new(id: UInt32(9700 + offset), parent: workspace.rootTilingContainer)
            return workspace
        }
        return (project.id, spaces)
    }

    private func shown(_ projectId: WorkspaceProjectId, _ spaces: [Workspace]) -> [WorkspaceId] {
        let ids = Set(spaces.map(\.id))
        return orderedWorkspaces(in: projectId).filter { ids.contains($0.id) }.map(\.id)
    }

    func testMoveBeforeAndToEnd() {
        let (projectId, s) = makeWorkspaces(3)
        XCTAssertTrue(moveWorkspaceInOrder(s[2], before: s[0]))
        XCTAssertEqual(shown(projectId, s), [s[2], s[0], s[1]].map(\.id))
        XCTAssertTrue(moveWorkspaceInOrder(s[2], before: nil))
        XCTAssertEqual(shown(projectId, s), [s[0], s[1], s[2]].map(\.id))
        XCTAssertFalse(moveWorkspaceInOrder(s[2], before: nil))
        XCTAssertTrue(s.allSatisfy { $0.projectId == projectId && $0.allLeafWindowsRecursive.count == 1 })
        XCTAssertEqual(s.map(\.name), ["reorder-0", "reorder-1", "reorder-2"])
    }

    func testMoveUpAndDownStopAtTheEnds() {
        let (projectId, s) = makeWorkspaces(3)
        XCTAssertTrue(moveWorkspaceInOrder(s[1], by: -1))
        XCTAssertEqual(shown(projectId, s), [s[1], s[0], s[2]].map(\.id))
        XCTAssertFalse(moveWorkspaceInOrder(s[1], by: -1))
        XCTAssertTrue(moveWorkspaceInOrder(s[1], by: 1))
        XCTAssertTrue(moveWorkspaceInOrder(s[1], by: 1))
        XCTAssertEqual(shown(projectId, s), [s[0], s[2], s[1]].map(\.id))
        XCTAssertFalse(moveWorkspaceInOrder(s[1], by: 1))
    }

    func testNumbersFollowTheNewOrder() {
        let (projectId, s) = makeWorkspaces(3)
        moveWorkspaceInOrder(s[2], before: s[0])
        let indices = automaticWorkspaceDisplayIndices(in: projectId)
        XCTAssertEqual([s[2], s[0], s[1]].map { indices[$0.id] }, [1, 2, 3])
    }

    // Restored numbers (here the reverse of the live order) are what the user sees; a move
    // starts from them.
    func testMoveAfterRestoreStartsFromTheShownOrder() {
        let (projectId, s) = makeWorkspaces(3, restored: true)
        XCTAssertEqual(shown(projectId, s), [s[2], s[1], s[0]].map(\.id))
        XCTAssertTrue(moveWorkspaceInOrder(s[0], by: -1))
        XCTAssertEqual(shown(projectId, s), [s[2], s[0], s[1]].map(\.id))
        XCTAssertTrue(s.allSatisfy { $0.restoredDisplayIndex == nil })
    }

    func testConfiguredPersistentWorkspaceKeepsItsSlot() {
        config.persistentWorkspaces = ["reorder-0"]
        let (_, s) = makeWorkspaces(2)
        XCTAssertFalse(moveWorkspaceInOrder(s[0], before: nil))
    }

    func testCommandMovesTheNamedWorkspace() async throws {
        let (projectId, s) = makeWorkspaces(2)
        let result = try await XCTUnwrap(parseCommand("move-workspace-order --workspace reorder-1 up").cmdOrDie)
            .run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(shown(projectId, s), [s[1], s[0]].map(\.id))
        XCTAssertNotNil(parseCommand("move-workspace-order sideways").errorOrNil)
    }

    // A new workspace takes the gap in restored numbers (1, new = 2, 3). Adopting the shown order
    // must keep every number where it is.
    func testAdoptingTheShownOrderKeepsANewWorkspaceInTheGapOfRestoredNumbers() {
        let (projectId, s) = makeWorkspaces(3)
        s[0].restoredDisplayIndex = 1
        s[1].restoredDisplayIndex = 3
        let before = automaticWorkspaceDisplayIndices(in: projectId)
        XCTAssertEqual([s[0], s[2], s[1]].map { before[$0.id] }, [1, 2, 3])
        adoptPresentedWorkspaceOrder(projectId)
        XCTAssertEqual(automaticWorkspaceDisplayIndices(in: projectId), before)
        XCTAssertEqual(shown(projectId, s), [s[0], s[2], s[1]].map(\.id))
    }

    // A move that changes nothing must leave the project's order and numbers alone.
    func testAMoveThatChangesNothingKeepsRestoredNumbers() {
        let (projectId, s) = makeWorkspaces(3, restored: true)
        let before = automaticWorkspaceDisplayIndices(in: projectId)
        // s[0] holds the last restored number, so moving it to the end changes nothing.
        XCTAssertFalse(moveWorkspaceInOrder(s[0], before: nil))
        XCTAssertEqual(automaticWorkspaceDisplayIndices(in: projectId), before)
        XCTAssertTrue(s.allSatisfy { $0.restoredDisplayIndex != nil })
    }

    // Persistent workspaces keep their slots, so a step past one is a step over it.
    func testMovingStepsOverConfiguredPersistentWorkspaces() {
        config.persistentWorkspaces = ["reorder-0"]
        let (projectId, s) = makeWorkspaces(3)
        XCTAssertTrue(moveWorkspaceInOrder(s[2], by: -1))
        XCTAssertEqual(shown(projectId, s).filter { $0 != s[0].id }, [s[2], s[1]].map(\.id))
        XCTAssertFalse(moveWorkspaceInOrder(s[2], by: -1), "Nothing movable is above it")
    }
}
