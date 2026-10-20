@testable import AppBundle
import XCTest

@MainActor
final class WorkspacePresentationOrderTest: WorkspaceTestCase {
    func testMixedRestoredAndExplicitNumericWorkspacesUseDisplayOrderWithoutMovingNamedSlots() async {
        let project = createWorkspaceProject()
        let names = ["restored-one", "Notes", "restored-three", "restored-four", "restored-five", "2"]
        let indices: [Int?] = [1, nil, 3, 4, 5, nil]
        let spaces = names.enumerated().map { offset, name in
            let workspace = Workspace.get(byName: name)
            workspace.assignProject(project.id)
            if let index = indices[offset] {
                workspace.markAsAutomaticallyNamed()
                workspace.restoredDisplayIndex = index
            }
            _ = TestWindow.new(id: UInt32(9800 + offset), parent: workspace.rootTilingContainer)
            return workspace
        }
        let expected = [spaces[0], spaces[1], spaces[5], spaces[2], spaces[3], spaces[4]].map(\.id)
        let ids = Set(spaces.map(\.id))
        XCTAssertEqual(orderedWorkspaces(in: project.id).filter { ids.contains($0.id) }.map(\.id), expected)
        XCTAssertEqual(orderedWorkspacesForPresentation().filter { ids.contains($0.id) }.map(\.id), expected)
        let rows = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus, workspaceLabels: [:], availableMonitors: monitors)
        XCTAssertEqual(rows.filter { names.contains($0.name) }.map(\.displayName),
            ["Workspace 1", "Workspace 2", "Workspace 3", "Workspace 4", "Workspace 5", "Workspace 6"])
        XCTAssertEqual(spaces.map(\.name), names) // Ordering must not rename or move window ownership.
        XCTAssertTrue(spaces.allSatisfy { $0.projectId == project.id && $0.allLeafWindowsRecursive.count == 1 })
    }
    func testRemovingEmptyWorkspaceKeepsLiveAutomaticNumbersInDisplayOrder() async {
        await assertLiveOrderAfterRemoval()
    }

    func testRemovingEmptyWorkspaceKeepsDisplayOrderWithConfiguredMinimum() async {
        config.minimumWorkspaceCount = 5
        await assertLiveOrderAfterRemoval()
    }

    private func assertLiveOrderAfterRemoval() async {
        let project = createWorkspaceProject()
        let names = ["live-one", "live-three", "live-four", "2", "live-five"]
        let indices: [Int?] = [1, 3, 4, nil, 5]
        let spaces = names.enumerated().map { offset, name in
            let workspace = Workspace.get(byName: name)
            workspace.assignProject(project.id)
            if let index = indices[offset] {
                workspace.markAsAutomaticallyNamed()
                workspace.restoredDisplayIndex = index
            }
            _ = TestWindow.new(id: UInt32(9900 + offset), parent: workspace.rootTilingContainer)
            return workspace
        }
        let spare = Workspace.get(byName: "empty-spare")
        spare.assignProject(project.id)
        removeWorkspaceFromRegistry(spare)
        XCTAssertTrue(spaces.allSatisfy { $0.restoredDisplayIndex == nil })
        let ids = Set(spaces.map(\.id))
        let expected = [spaces[0], spaces[3], spaces[1], spaces[2], spaces[4]].map(\.id)
        XCTAssertEqual(orderedWorkspaces(in: project.id).filter { ids.contains($0.id) }.map(\.id), expected)
        XCTAssertEqual(orderedWorkspacesForPresentation().filter { ids.contains($0.id) }.map(\.id), expected)
        let rows = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus, workspaceLabels: [:], availableMonitors: monitors)
        XCTAssertEqual(rows.filter { names.contains($0.name) }.map(\.displayName),
            ["Workspace 1", "Workspace 2", "Workspace 3", "Workspace 4", "Workspace 5"])
        XCTAssertEqual(spaces.map(\.name), names)
        XCTAssertTrue(spaces.allSatisfy { $0.projectId == project.id && $0.allLeafWindowsRecursive.count == 1 })
    }

}
