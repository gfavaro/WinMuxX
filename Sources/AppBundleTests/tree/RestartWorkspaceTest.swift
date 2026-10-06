@testable import AppBundle
import Foundation
import Common
import XCTest

@MainActor
final class RestartWorkspaceTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func identity(_ title: String, pid: Int32 = 10, launch: TimeInterval = 10,
                          app: String = "test.editor", document: String? = nil, identifier: String? = nil) -> RestartWindowIdentity {
        RestartWindowIdentity(bundleId: app, pid: pid, launchDate: Date(timeIntervalSince1970: launch), title: title,
            documentURL: document, accessibilityIdentifier: identifier)
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

    func testDocumentMatchSurvivesTitleChangeAndDistinguishesSameTitles() {
        let workspace = Workspace.get(byName: "3")
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        first.restartIdentity = identity("Report", document: "file:///one/report.txt")
        second.restartIdentity = identity("Report", document: "file:///two/report.txt")
        let reopened = identity("Report — modified", pid: 20, launch: 20, document: "file:///two/report.txt")
        let other = identity("Report", pid: 20, launch: 20, document: "file:///one/report.txt")
        XCTAssertEqual(matchRestartWindow(id: 99, identity: reopened,
            saved: [FrozenWindow(first), FrozenWindow(second)], live: [(99, reopened), (100, other)]), 2)
    }

    func testConflictingDocumentOrIdentifierCannotFallBackToSameTitle() {
        let workspace = Workspace.get(byName: "3")
        let original = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        original.restartIdentity = identity("Report", document: "file:///old.txt", identifier: "editor-one")
        for current in [identity("Report", pid: 20, launch: 20, document: "file:///different.txt"),
                        identity("Report", pid: 20, launch: 20, identifier: "editor-two")] {
            XCTAssertNil(matchRestartWindow(id: 99, identity: current,
                saved: [FrozenWindow(original)], live: [(99, current)]))
        }
    }

    func testIdentifierCanRestoreWithoutTitleButGenericIdentifiersRemainAmbiguous() {
        let workspace = Workspace.get(byName: "3")
        let original = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        original.restartIdentity = identity("", identifier: "editor")
        let current = identity("", pid: 20, launch: 20, identifier: "editor")
        XCTAssertEqual(matchRestartWindow(id: 99, identity: current,
            saved: [FrozenWindow(original)], live: [(99, current)]), 1)
        XCTAssertNil(matchRestartWindow(id: 99, identity: current,
            saved: [FrozenWindow(original)], live: [(99, current), (100, current)]))
    }

    func testSharedDocumentCanBeDisambiguatedByWindowIdentifier() {
        let workspace = Workspace.get(byName: "3")
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        first.restartIdentity = identity("Report", document: "file:///report.txt", identifier: "first")
        second.restartIdentity = identity("Report", document: "file:///report.txt", identifier: "second")
        let current = identity("New title", pid: 20, launch: 20, document: "file:///report.txt", identifier: "second")
        let other = identity("Report", pid: 20, launch: 20, document: "file:///report.txt", identifier: "first")
        XCTAssertEqual(matchRestartWindow(id: 99, identity: current,
            saved: [FrozenWindow(first), FrozenWindow(second)], live: [(99, current), (100, other)]), 2)
    }

    func testIdentityDecodesPreviousTitleOnlyFormat() throws {
        let old = Data(#"{"bundleId":"test.editor","pid":10,"launchDate":0,"title":"Report"}"#.utf8)
        let decoded = try JSONDecoder().decode(RestartWindowIdentity.self, from: old)
        XCTAssertNil(decoded.documentURL)
        XCTAssertNil(decoded.accessibilityIdentifier)
        XCTAssertEqual(decoded.title, "Report")
        let rich = identity("Report", document: "file:///report.txt", identifier: "editor")
        XCTAssertEqual(try JSONDecoder().decode(RestartWindowIdentity.self, from: JSONEncoder().encode(rich)), rich)
    }

    func testCollidingOldIdsSelectCorrectSnapshotByDocument() async throws {
        let firstWorkspace = Workspace.get(byName: "3")
        let first = TestWindow.new(id: 1, parent: firstWorkspace.rootTilingContainer)
        first.restartIdentity = identity("Report", document: "file:///first.txt")
        let firstWorld = snapshotCurrentFrozenWorld()
        first.unbindFromParent()
        let secondWorkspace = Workspace.get(byName: "5")
        let second = TestWindow.new(id: 1, parent: secondWorkspace.rootTilingContainer)
        second.restartIdentity = identity("Report", document: "file:///second.txt")
        let secondWorld = snapshotCurrentFrozenWorld()
        second.unbindFromParent()
        preparePersistedFrozenWorldForStartup(PersistedFrozenWorldEnvelope(version: 2, world: secondWorld,
            pending: [PendingRestartSnapshot(world: firstWorld, remainingWindowIds: [1])]))
        let current = TestWindow.new(id: 99, parent: focus.workspace.rootTilingContainer)
        current.restartIdentity = identity("Report", pid: 20, launch: 20, document: "file:///second.txt")
        let restored = try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: current)
        XCTAssertTrue(restored)
        XCTAssertEqual(current.nodeWorkspace?.name, "5")
        XCTAssertTrue(workspaceHasPendingRestartWindows("3"))
    }

    private func prepareDelayedWindow() -> TestWindow {
        let workspace = Workspace.get(byName: "5")
        let original = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        original.restartIdentity = identity("Report", document: "file:///report.txt")
        let world = snapshotCurrentFrozenWorld()
        original.unbindFromParent()
        preparePersistedFrozenWorldForStartup(PersistedFrozenWorldEnvelope(version: 2, world: world, pending: nil))
        let current = TestWindow.new(id: 99, parent: focus.workspace.rootTilingContainer)
        current.restartIdentity = identity("", pid: 20, launch: 20)
        trackPendingRestartWindow(current)
        return current
    }

    func testRetryRestoresWindowWhenDocumentBecomesAvailable() async throws {
        let current = prepareDelayedWindow()
        current.restartIdentity = identity("Changed title", pid: 20, launch: 20, document: "file:///report.txt")
        try await retryPendingRestartWindows()
        XCTAssertEqual(current.nodeWorkspace?.name, "5")
    }

    func testRetryDoesNotOverrideUserPlacement() async throws {
        let current = prepareDelayedWindow()
        current.bindAsFloatingWindow(to: Workspace.get(byName: "7"))
        current.restartIdentity = identity("Report", pid: 20, launch: 20, document: "file:///report.txt")
        try await retryPendingRestartWindows()
        XCTAssertEqual(current.nodeWorkspace?.name, "7")
        XCTAssertTrue(workspaceHasPendingRestartWindows("5"))
    }

    func testDeletingWorkspaceDiscardsItsPendingAssignments() async throws {
        let current = prepareDelayedWindow()
        removeWorkspaceFromRegistry(try XCTUnwrap(Workspace.existing(byName: "5")))
        current.restartIdentity = identity("Report", pid: 20, launch: 20, document: "file:///report.txt")
        try await retryPendingRestartWindows()
        XCTAssertNil(Workspace.existing(byName: "5"))
        XCTAssertEqual(pendingRestartWindowCount, 0)
    }

    func testLateArrivalPreservesCurrentProjectAndNumbering() async throws {
        let current = prepareDelayedWindow()
        let destination = try XCTUnwrap(Workspace.existing(byName: "5"))
        destination.restoredDisplayIndex = 5
        destination.assignProject("project-2")
        XCTAssertNil(destination.restoredDisplayIndex)
        current.restartIdentity = identity("Report", pid: 20, launch: 20, document: "file:///report.txt")
        try await retryPendingRestartWindows()
        XCTAssertEqual(current.nodeWorkspace, destination)
        XCTAssertEqual(destination.projectId, "project-2")
        XCTAssertNil(destination.restoredDisplayIndex)
    }

    func testDisplayUuidFollowsMonitorAfterRearrangementAndRejectsReplacement() {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let movedRect = Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080)
        let original = TestMonitor(displayUUID: "external", monitorAppKitNsScreenScreensId: 1,
            name: "External", rect: rect, visibleRect: rect, isMain: false)
        let moved = TestMonitor(displayUUID: "external", monitorAppKitNsScreenScreensId: 2,
            name: "External", rect: movedRect, visibleRect: movedRect, isMain: false)
        let replacement = TestMonitor(displayUUID: "replacement", monitorAppKitNsScreenScreensId: 1,
            name: "Replacement", rect: rect, visibleRect: rect, isMain: true)
        let frozen = FrozenMonitor(original)
        XCTAssertEqual(frozen.resolve(in: [replacement, moved])?.displayUUID, "external")
        XCTAssertEqual(frozen.preferredPoint(in: [replacement, moved]), movedRect.topLeftCorner)
        XCTAssertNil(frozen.resolve(in: [replacement]))
    }

    func testLegacyMonitorSnapshotRetainsCoordinateFallback() throws {
        let encoded = try JSONEncoder().encode(FrozenMonitor(mainMonitor))
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "displayUUID")
        let decoded = try JSONDecoder().decode(FrozenMonitor.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(decoded.resolve(in: [mainMonitor])?.rect.topLeftCorner, mainMonitor.rect.topLeftCorner)
    }

    func testDeletedWorkspaceIsNotRecreatedFromAnotherPendingWindowSnapshot() throws {
        let firstWorkspace = Workspace.get(byName: "3")
        let first = TestWindow.new(id: 1, parent: firstWorkspace.rootTilingContainer)
        first.restartIdentity = identity("First")
        let secondWorkspace = Workspace.get(byName: "5")
        let second = TestWindow.new(id: 2, parent: secondWorkspace.rootTilingContainer)
        second.restartIdentity = identity("Second")
        let world = snapshotCurrentFrozenWorld()
        first.unbindFromParent()
        second.unbindFromParent()
        preparePersistedFrozenWorldForStartup(PersistedFrozenWorldEnvelope(version: 2, world: world, pending: nil))
        removeWorkspaceFromRegistry(firstWorkspace)
        let saved = makeRestartEnvelope()
        resetPersistedFrozenWorldForTests()
        preparePersistedFrozenWorldForStartup(saved)
        XCTAssertNil(Workspace.existing(byName: "3"))
        XCTAssertTrue(workspaceHasPendingRestartWindows("5"))
    }
}
