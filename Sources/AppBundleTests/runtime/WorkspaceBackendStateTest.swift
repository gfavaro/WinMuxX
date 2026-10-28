import Common
@testable import NativeSpaces
import XCTest
@testable import AppBundle

@MainActor
final class WorkspaceBackendStateTest: WorkspaceTestCase {
    func testDefaultBackendRetainsVirtualCapabilities() {
        XCTAssertEqual(runtime.workspaceBackend.kind, .virtual)
        XCTAssertEqual(runtime.workspaceBackend.capabilities, .virtual)
        XCTAssertNil(runtime.workspaceBackend.native.observation)
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
        XCTAssertNil(runtime.workspaceBackend.native.observation)
    }

    func testBackendSelectionIsRuntimeScoped() {
        let first = WinMuxRuntime()
        let second = WinMuxRuntime()
        first.workspaceBackend.selectForStartup(.native)
        XCTAssertEqual(first.workspaceBackend.kind, .native)
        XCTAssertEqual(second.workspaceBackend.kind, .virtual)
    }

    func testNativeObservationCallbacksKeepTheirRuntimeAndStopIndependently() async {
        let first = WinMuxRuntime()
        let second = WinMuxRuntime()
        first.workspaceBackend.selectForStartup(.native)
        second.workspaceBackend.selectForStartup(.native)
        let firstPublished = expectation(description: "first runtime observation")
        let secondPublished = expectation(description: "second runtime observation")
        let snapshot = NativeSpacesSnapshot(displays: [], windows: [], readMilliseconds: 0, capturedAt: .now)
        let firstObserver = NativeSpacesObservation(read: { _, _ in snapshot }, topology: nil)
        let secondObserver = NativeSpacesObservation(read: { _, _ in snapshot }, topology: nil)
        defer {
            first.withValue { first.workspaceBackend.stop() }
            second.withValue { second.workspaceBackend.stop() }
        }
        first.withValue {
            first.workspaceBackend.native.startObservation(observer: firstObserver) { inventory, _ in
                if inventory.currentSnapshot != nil {
                    XCTAssertTrue(runtime === first)
                    firstPublished.fulfill()
                }
            }
        }
        second.withValue {
            second.workspaceBackend.native.startObservation(observer: secondObserver) { inventory, _ in
                if inventory.currentSnapshot != nil {
                    XCTAssertTrue(runtime === second)
                    secondPublished.fulfill()
                }
            }
        }
        await fulfillment(of: [firstPublished, secondPublished], timeout: 2)
        first.withValue { first.workspaceBackend.stop() }
        XCTAssertNil(first.workspaceBackend.native.observation)
        XCTAssertTrue(second.workspaceBackend.native.observation === secondObserver)
        XCTAssertNotNil(secondObserver.inventory.currentSnapshot)
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
    func testTopUpDisabledAndReenabledPreservesPendingCreation() {
        let backend = runtime.workspaceBackend
        backend.selectForStartup(.native, nativeTilingEnabled: true)
        config.persistentWorkspaces = ["1", "2"]
        let display = NativeSpaceDisplay(identifier: "Main", activeSpaceID: "1",
            spaces: [NativeSpace(id: "1", uuid: "a", type: 0)])
        let snapshot = NativeSpacesSnapshot(displays: [display], windows: [], readMilliseconds: 0, capturedAt: .now)
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(snapshot, for: inventory.invalidate()))
        var creations = 0
        backend.native.desktopTopUp.settleDelay = .zero
        backend.native.desktopTopUp.isAvailable = { true }
        backend.native.desktopTopUp.create = { _ in creations += 1; return 77 }
        let previous = TrayMenuModel.shared.isEnabled
        defer { TrayMenuModel.shared.isEnabled = previous; backend.stop() }
        TrayMenuModel.shared.isEnabled = false
        backend.native.topUpNativeDesktops(inventory)
        XCTAssertEqual(creations, 0)
        TrayMenuModel.shared.isEnabled = true
        backend.native.setTopUpEnabled(true)
        backend.native.topUpNativeDesktops(inventory)
        XCTAssertEqual(creations, 1)
        backend.native.setTopUpEnabled(false)
        backend.native.topUpNativeDesktops(inventory)
        backend.native.setTopUpEnabled(true)
        backend.native.topUpNativeDesktops(inventory)
        XCTAssertEqual(creations, 1, "A pending creation must not be repeated after re-enable")
    }

    func testTopUpTimerCoalescesAndStopCancelsIt() async {
        let backend = runtime.workspaceBackend
        backend.selectForStartup(.native, nativeTilingEnabled: true)
        backend.native.scheduleTopUpRead(after: .seconds(60))
        let first = backend.native.topUpTimer
        for _ in 0..<20 { backend.native.scheduleTopUpRead(after: .seconds(60)) }
        XCTAssertTrue(first?.isCancelled == true)
        let latest = backend.native.topUpTimer
        XCTAssertNotNil(latest)
        backend.stop()
        XCTAssertTrue(latest?.isCancelled == true)
        XCTAssertNil(backend.native.topUpTimer)
        await latest?.value
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
        XCTAssertTrue(virtual.workspaceBackend.ui.hasProjects)
        XCTAssertFalse(native.workspaceBackend.ui.hasProjects)
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
            XCTAssertFalse(native.workspaceBackend.native.tiling.ready, "Native tiling stops writing")
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

private actor BackendReadGate {
    private var continuations: [CheckedContinuation<NativeSpacesSnapshot, Error>] = []
    let started: @Sendable (Int) -> Void
    init(started: @escaping @Sendable (Int) -> Void) { self.started = started }
    func read() async throws -> NativeSpacesSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            started(continuations.count)
        }
    }
    func finish(_ index: Int, _ snapshot: NativeSpacesSnapshot) {
        continuations[index].resume(returning: snapshot)
    }
}

@MainActor
final class NativeBackendIntegrationTest: WorkspaceTestCase {
    private func snapshot(_ ids: [String]) -> NativeSpacesSnapshot {
        NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "Main", activeSpaceID: "1",
            spaces: ids.map { NativeSpace(id: $0, uuid: "uuid-\($0)", type: 0) })],
            windows: [], readMilliseconds: 0, capturedAt: .now)
    }

    func testUISelectionRetainsIdentityAcrossAnInFlightRenumberOrRemoval() async throws {
        for removed in [false, true] {
            let initialRead = expectation(description: "initial read")
            let heldRead = expectation(description: "held read")
            let initialPublished = expectation(description: "initial published")
            let freshPublished = expectation(description: "fresh published")
            let gate = BackendReadGate { index in
                if index == 1 { initialRead.fulfill() } else if index == 2 { heldRead.fulfill() }
            }
            let observer = NativeSpacesObservation(read: { _, _ in try await gate.read() }, topology: nil)
            let backend = runtime.workspaceBackend
            backend.selectForStartup(.native)
            let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
            setMonitorsForTests([TestMonitor(displayUUID: "Main", monitorAppKitNsScreenScreensId: 1,
                name: "fixture", rect: rect, visibleRect: rect, isMain: true)])
            backend.native.startObservation(observer: observer) { inventory, event in
                if inventory.currentSnapshot != nil {
                    if event == "initial" { initialPublished.fulfill() } else { freshPublished.fulfill() }
                }
            }
            await fulfillment(of: [initialRead], timeout: 2)
            await gate.finish(0, snapshot(["1", "2", "3"]))
            await fulfillment(of: [initialPublished], timeout: 2)
            let workspace = try XCTUnwrap(backend.native.layouts.retainedByUUID["uuid-3"])
            observer.requestRead(event: "activeSpaceDidChange")
            await fulfillment(of: [heldRead], timeout: 2)
            var posts: [String] = []
            var active = "1"
            let updated = removed ? ["1", "2"] : ["1", "3", "2"]
            backend.native.navigation.isSupported = { true }
            backend.native.navigation.canPostEvents = { true }
            backend.native.navigation.pollInterval = .milliseconds(1)
            backend.native.navigation.topology = {
                [NativeSpaceDisplay(identifier: "Main", activeSpaceID: active,
                    spaces: updated.map { NativeSpace(id: $0, uuid: "uuid-\($0)", type: 0) })]
            }
            backend.native.navigation.post = { plan in posts.append(plan.targetSpaceID); active = plan.targetSpaceID; return true }
            let started = expectation(description: "UI selection started")
            let selection = Task { started.fulfill(); return try await selectWorkspaceFromUi(workspace.name) }
            await fulfillment(of: [started], timeout: 2)
            await gate.finish(1, snapshot(updated))
            await fulfillment(of: [freshPublished], timeout: 2)
            let error = try await selection.value
            if removed {
                XCTAssertTrue(error?.contains("no longer exists") == true)
                XCTAssertTrue(posts.isEmpty)
            } else {
                XCTAssertNil(error)
                XCTAssertEqual(posts, ["3"])
            }
            backend.stop()
            setUpWorkspacesForTests()
        }
    }

    func testTimerAndObserverCoalesceAndCancellationPreventsRead() async throws {
        let first = expectation(description: "initial read")
        let second = expectation(description: "coalesced read")
        let published = expectation(description: "published")
        let gate = BackendReadGate { index in
            if index == 1 { first.fulfill() } else if index == 2 { second.fulfill() } else { XCTFail("Unexpected read") }
        }
        let observer = NativeSpacesObservation(read: { _, _ in try await gate.read() }, topology: nil)
        let backend = runtime.workspaceBackend
        backend.selectForStartup(.native, nativeTilingEnabled: true)
        let enabled = TrayMenuModel.shared.isEnabled
        TrayMenuModel.shared.isEnabled = true
        defer { backend.stop(); TrayMenuModel.shared.isEnabled = enabled }
        backend.native.startObservation(observer: observer) { inventory, _ in if inventory.currentSnapshot != nil { published.fulfill() } }
        await fulfillment(of: [first], timeout: 2)
        for _ in 0..<30 { observer.requestRead(event: "activeSpaceDidChange") }
        backend.native.scheduleTopUpRead(after: .milliseconds(10))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(observer.snapshotReadCount, 1)
        await gate.finish(0, snapshot(["1"]))
        await fulfillment(of: [second], timeout: 2)
        await gate.finish(1, snapshot(["1"]))
        await fulfillment(of: [published], timeout: 2)
        XCTAssertEqual(observer.snapshotReadCount, 2)
        backend.native.scheduleTopUpRead(after: .milliseconds(20))
        backend.native.cancelTopUpRead()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(observer.snapshotReadCount, 2)
    }

    func testConfirmationTimeoutTriggersReadWithoutAnotherEvent() async {
        let observer = NativeSpacesObservation(read: { [snapshot = snapshot(["1"])] _, _ in snapshot }, topology: nil)
        let backend = runtime.workspaceBackend
        backend.selectForStartup(.native, nativeTilingEnabled: true)
        config.persistentWorkspaces = ["1", "2"]
        let enabled = TrayMenuModel.shared.isEnabled
        TrayMenuModel.shared.isEnabled = true
        defer { backend.stop(); TrayMenuModel.shared.isEnabled = enabled }
        backend.native.desktopTopUp.settleDelay = .zero
        backend.native.desktopTopUp.confirmTimeout = .milliseconds(30)
        backend.native.desktopTopUp.isAvailable = { true }
        var creations = 0
        backend.native.desktopTopUp.create = { _ in creations += 1; return 77 }
        backend.native.startObservation(observer: observer) { _, _ in }
        // The observer invokes the callback before top-up updates its status; watch the
        // subsequent state via a bounded task instead.
        let deadline = ContinuousClock.now + .seconds(2)
        while !backend.native.desktopTopUp.status.contains("did not appear"), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(backend.native.desktopTopUp.status, "stopped: desktop 2 did not appear")
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(observer.snapshotReadCount, 3)
    }
}
