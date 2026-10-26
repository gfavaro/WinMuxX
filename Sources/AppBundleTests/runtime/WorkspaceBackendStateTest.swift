import XCTest
@testable import AppBundle

@MainActor
final class WorkspaceBackendStateTest: WorkspaceTestCase {
    func testDefaultBackendRetainsVirtualCapabilities() {
        XCTAssertEqual(runtime.workspaceBackend.kind, .virtual)
        XCTAssertEqual(runtime.workspaceBackend.capabilities, .virtual)
        XCTAssertNil(runtime.workspaceBackend.observation)
    }

    func testNativeObservationCannotBorrowVirtualOwnershipOrRecovery() async throws {
        let workspace = Workspace.get(byName: "retained")
        let root = workspace.rootTilingContainer
        let id = workspace.id
        runtime.workspaceBackend.selectForStartup(.native)
        XCTAssertEqual(runtime.workspaceBackend.capabilities, .nativeObservation)
        refreshModel()
        try await runRefreshSessionBlocking(.startup)
        XCTAssertTrue(Workspace.existing(byName: "retained") === workspace)
        XCTAssertTrue(workspace.rootTilingContainer === root)
        XCTAssertEqual(workspace.id, id)
        XCTAssertFalse(loadPersistedFrozenWorldForStartupIfPresent())
        XCTAssertNil(runtime.workspaceBackend.observation)
    }

    func testBackendSelectionIsRuntimeScoped() {
        let first = WinMuxRuntime()
        let second = WinMuxRuntime()
        first.workspaceBackend.selectForStartup(.native)
        XCTAssertEqual(first.workspaceBackend.kind, .native)
        XCTAssertEqual(second.workspaceBackend.kind, .virtual)
    }

    func testNativeWindowChangesCannotPopulateVirtualClosedWindowRecovery() {
        let saved = runtime.recovery.closedWindows.windowIds
        let workspace = Workspace.get(byName: "native-test")
        TestWindow.new(id: 999, parent: workspace.rootTilingContainer)
        runtime.workspaceBackend.selectForStartup(.native)
        cacheClosedWindowIfNeeded()
        syncClosedWindowsCacheToCurrentWorld()
        XCTAssertEqual(runtime.recovery.closedWindows.windowIds, saved)
    }
}
