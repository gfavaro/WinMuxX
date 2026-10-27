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

final class TestWriteGuardTest: XCTestCase {
    func testOnlyTemporaryPathsAreWritableFromTests() {
        XCTAssertTrue(isTemporaryPath(FileManager.default.temporaryDirectory.appendingPathComponent("native.json")))
        XCTAssertTrue(isTemporaryPath(URL(filePath: "/tmp/x/config.toml")))
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertFalse(isTemporaryPath(home.appendingPathComponent(".config/winmuxx/winmux.toml")), "The user's config")
        XCTAssertFalse(isTemporaryPath(home.appendingPathComponent("Library/Application Support/WinMux-GF/window-state.json")))
        XCTAssertFalse(isTemporaryPath(URL(filePath: "/tmpfoo/x")), "A prefix of a temporary name is not temporary")
    }
}

final class MacAppTeardownTest: XCTestCase {
    /// A thread-guarded value left out of destroy() crashes WinMuxX whenever an app quits.
    func testEveryThreadGuardedValueIsDestroyed() throws {
        let source = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "AppBundle/tree/MacApp.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let guarded = text.matches(of: /let (\w+): ThreadGuardedValue</).map { String($0.1) }
        XCTAssertFalse(guarded.isEmpty)
        for name in guarded {
            XCTAssertTrue(text.contains("\(name).destroy()"), "\(name) is never destroyed in MacApp.destroy()")
        }
    }
}

@MainActor
final class NativeEnableTest: XCTestCase {
    func testDisablingPausesNativeTilingAndEnablingResumesIt() async throws {
        setUpWorkspacesForTests()
        let native = WinMuxRuntime()
        native.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        let wasEnabled = TrayMenuModel.shared.isEnabled
        defer { TrayMenuModel.shared.isEnabled = wasEnabled }
        try await native.withValue {
            let io = CmdIo(stdin: .emptyStdin)
            let off = try XCTUnwrap(parseCommand("enable off").unwrap().0)
            let disabled = try await native.workspaceBackend.current.run(off, env: .defaultEnv, io: io)
            XCTAssertEqual(disabled, true, io.stderr.joined())
            XCTAssertFalse(TrayMenuModel.shared.isEnabled)
            XCTAssertFalse(native.workspaceBackend.nativeTiling.ready, "Native tiling stops writing")
            let on = try XCTUnwrap(parseCommand("enable on").unwrap().0)
            let enabled = try await native.workspaceBackend.current.run(on, env: .defaultEnv, io: io)
            XCTAssertEqual(enabled, true)
            XCTAssertTrue(TrayMenuModel.shared.isEnabled)
            XCTAssertTrue(native.workspaceBackend.accepts(try XCTUnwrap(parseCommand("focus-back-and-forth").unwrap().0)))
            XCTAssertTrue(native.workspaceBackend.accepts(try XCTUnwrap(parseCommand("exec-and-forget true").unwrap().0)))
            XCTAssertTrue(native.workspaceBackend.accepts(try XCTUnwrap(parseCommand("flatten-workspace-tree").unwrap().0)))
        }
    }
}

final class UnclassifiedWindowsTest: XCTestCase {
    func testSkipsBrieflyAndForgetsOnEventsAboutTheWindowOrItsApp() {
        var clock = ContinuousClock.now
        var cache = UnclassifiedWindows()
        cache.now = { clock }
        cache.note(1, pid: 100)
        cache.note(2, pid: 100)
        cache.note(3, pid: 200)
        XCTAssertTrue(cache.skips(1))
        cache.forget(windowID: 1)
        XCTAssertFalse(cache.skips(1), "An event about the window retries it")
        cache.forget(pid: 100)
        XCTAssertFalse(cache.skips(2), "The app's own window events retry all of its windows")
        XCTAssertTrue(cache.skips(3))
        clock = clock.advanced(by: .seconds(6))
        XCTAssertFalse(cache.skips(3), "Every window is retried after the TTL")
    }
}
