@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class WorkspaceOverviewModelTest: XCTestCase {
    private var world: WorkspaceNavigationFixture!
    override func setUp() async throws { world = WorkspaceNavigationFixture() }
    override func tearDown() async throws { world.cleanUp(); world = nil }

    func testInactiveWorkspaceUsesSavedLayoutAndDoesNotMutateWorld() throws {
        let inactive = world.spaces[2]
        inactive.seedMonitorIfNeeded(world.displays[0])
        let window = try XCTUnwrap(inactive.allLeafWindowsRecursive.first)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 100, topLeftY: 200, width: 800, height: 600)
        let before = Workspace.all.map(\.id)
        let focusBefore = focus
        let visibleBefore = world.displays.map { $0.activeWorkspace.id }
        let cards = buildWorkspaceOverviewCards(project: focus.workspace.projectId, monitors: world.displays)
        let card = try XCTUnwrap(cards.first { $0.id == inactive.id })
        XCTAssertFalse(inactive.isVisible)
        XCTAssertEqual(card.windows.first?.frame?.minX ?? -1, 100.0 / 1920, accuracy: 0.00001)
        XCTAssertEqual(card.windows.first?.frame?.height ?? -1, 600.0 / 1080, accuracy: 0.00001)
        XCTAssertEqual(Workspace.all.map(\.id), before)
        XCTAssertEqual(focus.workspace.id, focusBefore.workspace.id)
        XCTAssertTrue(focus.windowOrNil === focusBefore.windowOrNil)
        XCTAssertEqual(world.displays.map { $0.activeWorkspace.id }, visibleBefore)
    }

    func testRestoredPreviewSurvivesParkingAndOldSnapshotsRemainReadable() throws {
        let workspace = world.spaces[2]
        workspace.seedMonitorIfNeeded(world.displays[0])
        let window = try XCTUnwrap(workspace.allLeafWindowsRecursive.first)
        let saved = CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
        window.workspacePreviewFrame = saved
        let encoded = try JSONEncoder().encode(FrozenWindow(window))
        window.workspacePreviewFrame = nil
        applyFrozenWindowState(window, try JSONDecoder().decode(FrozenWindow.self, from: encoded))
        // Cold-start native and layout caches may still contain a parking strip.
        window.recordAuthoritativeActualRect(Rect(topLeftX: 1919, topLeftY: 1079, width: 800, height: 600))
        window.lastAppliedLayoutPhysicalRect = window.lastKnownActualRect
        let card = try XCTUnwrap(buildWorkspaceOverviewCards(project: workspace.projectId, monitors: world.displays).first { $0.id == workspace.id })
        XCTAssertEqual(card.windows.first?.frame, saved)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "workspacePreviewFrame")
        let decoded = try JSONDecoder().decode(FrozenWindow.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.workspacePreviewFrame)
    }

    func testParkingStripsAndInvalidSavedFramesAreRejected() throws {
        let desktop = CGSize(width: 1920, height: 1080)
        for frame in [CGRect(x: 1919, y: 1079, width: 800, height: 600),
                      CGRect(x: -799, y: 1079, width: 800, height: 600),
                      CGRect(x: 2500, y: 0, width: 800, height: 600)] {
            XCTAssertNil(normalizedWorkspacePreviewFrame(frame, origin: .zero, desktopSize: desktop))
        }
        let window = try XCTUnwrap(world.spaces[0].allLeafWindowsRecursive.first)
        window.workspacePreviewFrame = CGRect(x: 2, y: 2, width: 1, height: 1)
        let invalid = FrozenWindow(window)
        window.workspacePreviewFrame = nil
        applyFrozenWindowState(window, invalid)
        XCTAssertNil(window.workspacePreviewFrame)
    }

    func testVisibleWorkspaceUsesCurrentFrameInsteadOfPreviousParkingSnapshot() throws {
        let workspace = world.spaces[0]
        let window = try XCTUnwrap(workspace.allLeafWindowsRecursive.first)
        window.workspacePreviewFrame = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        window.recordAuthoritativeActualRect(Rect(topLeftX: 100, topLeftY: 200, width: 800, height: 600))
        let card = try XCTUnwrap(buildWorkspaceOverviewCards(project: workspace.projectId, monitors: world.displays).first { $0.id == workspace.id })
        XCTAssertEqual(card.windows.first?.frame?.minX ?? -1, 100.0 / 1920, accuracy: 0.00001)
    }

    func testNativeStateAndMissingGeometryFiltering() throws {
        let workspace = world.spaces[0]
        let window = try XCTUnwrap(workspace.allLeafWindowsRecursive.first)
        window.lastAppliedLayoutPhysicalRect = nil
        var cards = buildWorkspaceOverviewCards(project: workspace.projectId, monitors: world.displays)
        XCTAssertNil(cards.first { $0.id == workspace.id }?.windows.first?.frame)
        window.recordObservedNativeState(fullscreen: false, minimized: true, token: window.nativeStateObservationToken())
        cards = buildWorkspaceOverviewCards(project: workspace.projectId, monitors: world.displays)
        XCTAssertTrue(cards.first { $0.id == workspace.id }?.windows.isEmpty == true)
        window.recordObservedNativeState(fullscreen: true, minimized: false, token: window.nativeStateObservationToken())
        cards = buildWorkspaceOverviewCards(project: workspace.projectId, monitors: world.displays)
        XCTAssertTrue(cards.first { $0.id == workspace.id }?.windows.isEmpty == true)
    }

    func testWorkspaceOwnershipAndProjectScopeFollowExistingPolicy() throws {
        let cards = buildWorkspaceOverviewCards(project: focus.workspace.projectId, monitors: world.displays)
        for card in cards {
            let workspace = try XCTUnwrap(Workspace.existing(byName: card.name))
            XCTAssertEqual(card.monitor, MonitorViewportId(workspace.workspaceMonitor))
        }
        XCTAssertEqual(cards.map(\.id), orderedUserFacingWorkspaces(in: focus.workspace.projectId).map(\.id))
        XCTAssertTrue(buildWorkspaceOverviewCards(project: "nonexistent-project", monitors: world.displays).isEmpty)
        XCTAssertTrue(buildWorkspaceOverviewCards(project: focus.workspace.projectId, monitors: []).isEmpty)
    }
    func testSelectionRejectsReusedWindowIdentityAndNativeMinimization() async throws {
        let workspace = world.spaces[2]
        workspace.seedMonitorIfNeeded(world.displays[0])
        let original = try XCTUnwrap(workspace.allLeafWindowsRecursive.first)
        let card = try XCTUnwrap(buildWorkspaceOverviewCards(project: focus.workspace.projectId, monitors: world.displays).first { $0.id == workspace.id })
        let selected = try XCTUnwrap(card.windows.first)
        let visibleBefore = world.displays.map { $0.activeWorkspace.id }
        original.unbindFromParent()
        let replacement = TestWindow.new(id: original.windowId, parent: workspace.rootTilingContainer)
        var result = await WorkspaceOverviewDependencies.live.activate(card, selected)
        XCTAssertFalse(result)
        XCTAssertEqual(world.displays.map { $0.activeWorkspace.id }, visibleBefore)
        let freshCard = try XCTUnwrap(buildWorkspaceOverviewCards(project: focus.workspace.projectId, monitors: world.displays).first { $0.id == workspace.id })
        replacement.nativeIsMacosMinimized = true
        result = await WorkspaceOverviewDependencies.live.activate(freshCard, freshCard.windows.first)
        XCTAssertFalse(result)
        XCTAssertEqual(world.displays.map { $0.activeWorkspace.id }, visibleBefore)
    }

    func testSelectingWorkspaceOnAnotherDisplayPreservesAllViewports() async throws {
        let workspace = world.spaces[1]
        let card = try XCTUnwrap(buildWorkspaceOverviewCards(project: focus.workspace.projectId, monitors: world.displays).first { $0.id == workspace.id })
        let before = world.displays.map { $0.activeWorkspace.id }
        let result = await WorkspaceOverviewDependencies.live.activate(card, card.windows.first)
        XCTAssertTrue(result)
        XCTAssertEqual(focus.workspace.id, workspace.id)
        XCTAssertEqual(world.displays.map { $0.activeWorkspace.id }, before)
    }

}
