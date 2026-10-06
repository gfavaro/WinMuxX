@testable import AppBundle
import Foundation
import XCTest

@MainActor
final class RestartWorkspaceTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func identity(_ title: String, pid: Int32 = 10, launch: TimeInterval = 10,
                          app: String = "test.editor") -> RestartWindowIdentity {
        RestartWindowIdentity(bundleId: app, pid: pid, launchDate: Date(timeIntervalSince1970: launch), title: title)
    }

    func testReopenedWindowReturnsToSameNumberedWorkspaceAndProject() async throws {
        let workspace = Workspace.get(byName: "5")
        workspace.assignProject("project-2")
        let original = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        original.restartIdentity = identity("Report")
        let world = snapshotCurrentFrozenWorld()
        original.unbindFromParent()
        removeWorkspaceFromRegistry(workspace)
        preparePersistedFrozenWorldForStartup(PersistedFrozenWorldEnvelope(version: 2, world: world, pending: nil))
        Workspace.reconcileWorkspaceState()
        XCTAssertNotNil(Workspace.existing(byName: "5"))
        let reopened = TestWindow.new(id: 99, parent: focus.workspace.rootTilingContainer)
        reopened.restartIdentity = identity("Report", pid: 20, launch: 20)
        let restored = try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: reopened)
        XCTAssertTrue(restored)
        XCTAssertEqual(reopened.nodeWorkspace?.name, "5")
        XCTAssertEqual(reopened.nodeWorkspace?.projectId, "project-2")
        XCTAssertFalse(workspaceHasPendingRestartWindows("5"))
    }

    func testRecycledIdDoesNotInheritAnotherAppsWorkspace() async throws {
        let workspace = Workspace.get(byName: "3")
        let original = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        original.restartIdentity = identity("Report")
        let world = snapshotCurrentFrozenWorld()
        original.unbindFromParent()
        preparePersistedFrozenWorldForStartup(PersistedFrozenWorldEnvelope(version: 2, world: world, pending: nil))
        let unrelated = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        unrelated.restartIdentity = identity("Report", app: "test.browser")
        let restored = try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: unrelated)
        XCTAssertFalse(restored)
        XCTAssertNotEqual(unrelated.nodeWorkspace?.name, "3")
    }

    func testAmbiguousSavedOrLiveTitlesAreNotGuessed() {
        let workspace = Workspace.get(byName: "3")
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        first.restartIdentity = identity("Untitled")
        second.restartIdentity = identity("Untitled")
        let liveIdentity = identity("Untitled", pid: 20, launch: 20)
        XCTAssertNil(matchRestartWindow(id: 99, identity: liveIdentity,
            saved: [FrozenWindow(first), FrozenWindow(second)], live: [(99, liveIdentity)]))
        XCTAssertNil(matchRestartWindow(id: 99, identity: liveIdentity,
            saved: [FrozenWindow(first)], live: [(99, liveIdentity), (100, liveIdentity)]))
        XCTAssertEqual(matchRestartWindow(id: 1, identity: identity("Changed title"),
            saved: [FrozenWindow(first), FrozenWindow(second)], live: [(1, identity("Changed title"))]), 1)
    }

    func testMissingFirstWindowDoesNotBlockRestoringLaterSibling() async throws {
        let workspace = Workspace.get(byName: "5")
        let missing = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let later = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        let world = snapshotCurrentFrozenWorld()
        missing.unbindFromParent()
        later.unbindFromParent()
        let reopened = TestWindow.new(id: 99, parent: focus.workspace.rootTilingContainer)
        let restored = try await restoreFrozenWorldIfNeeded(world, newlyDetectedWindow: reopened,
            matchedWindows: [2: reopened], restoreVisibleWorkspaces: false)
        XCTAssertTrue(restored)
        XCTAssertEqual(reopened.nodeWorkspace?.name, "5")
        XCTAssertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.contains(reopened))
    }

    func testLateLaunchDoesNotMoveAlreadyRestoredWindowBack() async throws {
        let workspace = Workspace.get(byName: "3")
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        first.restartIdentity = identity("First")
        second.restartIdentity = identity("Second")
        let world = snapshotCurrentFrozenWorld()
        first.unbindFromParent()
        second.unbindFromParent()
        preparePersistedFrozenWorldForStartup(PersistedFrozenWorldEnvelope(version: 2, world: world, pending: nil))
        let reopenedFirst = TestWindow.new(id: 99, parent: focus.workspace.rootTilingContainer)
        reopenedFirst.restartIdentity = identity("First", pid: 20, launch: 20)
        let firstRestored = try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: reopenedFirst)
        XCTAssertTrue(firstRestored)
        reopenedFirst.bindAsFloatingWindow(to: Workspace.get(byName: "7"))
        let reopenedSecond = TestWindow.new(id: 100, parent: focus.workspace.rootTilingContainer)
        reopenedSecond.restartIdentity = identity("Second", pid: 20, launch: 20)
        let secondRestored = try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: reopenedSecond)
        XCTAssertTrue(secondRestored)
        XCTAssertEqual(reopenedSecond.nodeWorkspace?.name, "3")
        XCTAssertEqual(reopenedFirst.nodeWorkspace?.name, "7")
    }

    func testAutomaticWorkspaceKeepsItsSavedDisplayNumber() async throws {
        let first = Workspace.get(byName: "__internal_auto_workspace_1")
        first.markAsAutomaticallyNamed()
        let second = Workspace.get(byName: "__internal_auto_workspace_2")
        second.markAsAutomaticallyNamed()
        let one = TestWindow.new(id: 1, parent: first.rootTilingContainer)
        let two = TestWindow.new(id: 2, parent: second.rootTilingContainer)
        one.restartIdentity = identity("First")
        two.restartIdentity = identity("Second")
        let savedIndex = automaticWorkspaceDisplayIndex(second, focusedWorkspace: first)
        let world = snapshotCurrentFrozenWorld()
        one.unbindFromParent()
        two.unbindFromParent()
        removeWorkspaceFromRegistry(first)
        removeWorkspaceFromRegistry(second)
        preparePersistedFrozenWorldForStartup(PersistedFrozenWorldEnvelope(version: 2, world: world, pending: nil))
        Workspace.reconcileWorkspaceState()
        let restored = try XCTUnwrap(Workspace.existing(byName: second.name))
        XCTAssertEqual(automaticWorkspaceDisplayIndex(restored, focusedWorkspace: focus.workspace), savedIndex)
        XCTAssertTrue(isUserFacingWorkspace(restored))
    }

    func testCorruptPrimaryFallsBackToLastReadableSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("window-state.json")
        let workspace = Workspace.get(byName: "5")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.restartIdentity = identity("Report")
        try saveRestartEnvelope(makeRestartEnvelope(), to: url)
        window.bindAsFloatingWindow(to: Workspace.get(byName: "7"))
        try saveRestartEnvelope(makeRestartEnvelope(), to: url)
        try Data("broken".utf8).write(to: url)
        let recovered = try XCTUnwrap(loadRestartEnvelope(from: url))
        XCTAssertEqual(recovered.world.workspaces.first { collectFrozenWindows($0)[1] != nil }?.name, "5")
    }

    func testPendingWindowSurvivesSavingAndAnotherRestart() async throws {
        let workspace = Workspace.get(byName: "5")
        let original = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        original.restartIdentity = identity("Report")
        rememberRestartWindowBeforeAppTermination(original)
        original.unbindFromParent()
        let persisted = try JSONDecoder().decode(PersistedFrozenWorldEnvelope.self,
            from: JSONEncoder().encode(makeRestartEnvelope()))
        resetPersistedFrozenWorldForTests()
        preparePersistedFrozenWorldForStartup(persisted)
        let reopened = TestWindow.new(id: 99, parent: focus.workspace.rootTilingContainer)
        reopened.restartIdentity = identity("Report", pid: 20, launch: 20)
        let restored = try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: reopened)
        XCTAssertTrue(restored)
        XCTAssertEqual(reopened.nodeWorkspace?.name, "5")
    }

    func testOldIdOnlyStateCannotMoveAnUnrelatedWindow() async throws {
        let workspace = Workspace.get(byName: "5")
        let original = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let legacy = snapshotCurrentFrozenWorld()
        original.unbindFromParent()
        preparePersistedFrozenWorldForStartup(PersistedFrozenWorldEnvelope(version: 1, world: legacy, pending: nil))
        let unrelated = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        unrelated.restartIdentity = identity("Other")
        let restored = try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: unrelated)
        XCTAssertFalse(restored)
        XCTAssertFalse(workspaceHasPendingRestartWindows("5"))
    }
}
