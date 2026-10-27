import Common
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

    func testNativeLeavesUnimplementedShortcutsToMacOS() async throws {
        let bindings = parseConfig("""
        [mode.main.binding]
        ctrl-left = 'workspace prev'
        ctrl-down = 'move-node-to-monitor 2'
        alt-h = 'focus left'
        alt-b = ['balance-sizes', 'workspace 2']
        [mode.main.binding-tap]
        left-alt = 'focus-monitor next'
        """).config
        config = bindings
        defer { resetHotKeys() }
        try await activateMode(mainModeId)
        XCTAssertEqual(runtime.hotkeys.hotkeys.count, 4)
        XCTAssertEqual(runtime.hotkeys.activeTapBindings.count, 1)
        resetHotKeys()

        let native = WinMuxRuntime()
        native.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        try await native.withValue {
            config = bindings
            defer { resetHotKeys() }
            try await activateMode(mainModeId)
            // Monitor moves and focus are native; navigation can't share a sequence with window commands.
            XCTAssertEqual(Set(runtime.hotkeys.hotkeys.values.compactMap(\.keyCombo.key)), [.h, .downArrow, .leftArrow])
            XCTAssertEqual(runtime.hotkeys.activeTapBindings.count, 1)
        }
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

@MainActor
final class NativeObservationChromeTest: XCTestCase {
    func testABurstOfCompletedReadsRefreshesChromeOnce() async throws {
        let chrome = NativeObservationChrome()
        for _ in 0..<5 { chrome.schedule() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(chrome.requests, 5)
        XCTAssertEqual(chrome.refreshes, 1)
    }
}

@MainActor
final class WorkspaceBackendInterfaceTest: XCTestCase {
    func testEachBackendAnswersForItselfAndOnlyNativeClaimsCommands() async throws {
        let virtual = WinMuxRuntime()
        let native = WinMuxRuntime()
        native.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        XCTAssertTrue(virtual.workspaceBackend.current is VirtualWorkspaceBackend)
        XCTAssertTrue(native.workspaceBackend.current is NativeWorkspaceBackend)
        let workspace = try XCTUnwrap(parseCommand("workspace 2").unwrap().0)
        let io = CmdIo(stdin: .emptyStdin)
        let claimed = try await virtual.withValue { try await virtual.workspaceBackend.current.run(workspace, env: .defaultEnv, io: io) }
        XCTAssertNil(claimed, "Virtual runs the shared implementation")
        let focusLeft = try XCTUnwrap(parseCommand("focus left").unwrap().0)
        let passed = try await native.withValue { try await native.workspaceBackend.current.run(focusLeft, env: .defaultEnv, io: io) }
        XCTAssertNil(passed, "Native leaves tiling commands to the shared implementation and its fence")
        XCTAssertTrue(virtual.workspaceBackend.current.hasProjects)
        XCTAssertFalse(native.workspaceBackend.current.hasProjects)
    }
}
