@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor final class ModeLeaderTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config = parseConfig("""
        [mode.leader]
        timeout-ms = 1500
        show-indicator = true
        indicator-color = '#5e9eff'
        [mode.leader.binding]
        esc = 'mode main'
        h = 'focus left'
        [mode.main.binding]
        alt-space = 'mode leader'
        """).config
        TrayMenuModel.shared.isEnabled = true
    }
    override func tearDown() async throws { resetHotKeys(); setUpWorkspacesForTests() }

    func testConfigValidationAndLegacyDefaults() {
        XCTAssertEqual(config.modes["leader"]?.indicatorColor, "#5E9EFF")
        XCTAssertEqual(config.modes["main"]?.timeoutMs, 0)
        XCTAssertEqual(config.modes["main"]?.showIndicator, false)
        for body in ["timeout-ms = -1", "timeout-ms = 60001", "timeout-ms = true", "timeout-ms = 1.5", "show-indicator = 'yes'", "indicator-color = '#fff'"] {
            XCTAssertFalse(parseConfig("[mode.main]\n[mode.test]\n" + body).errors.isEmpty, body)
        }
        for timeout in [0, 60000] { XCTAssertTrue(parseConfig("[mode.main]\n[mode.test]\ntimeout-ms = \(timeout)").errors.isEmpty) }
    }

    func testOneShotDeadlineReentryAndStaleCompletion() async throws {
        var fires: [@MainActor () -> Void] = []
        var delays: [Int] = []
        runtime.hotkeys.modeSession.schedule = { ms, fire in delays.append(ms); fires.append(fire); return {} }
        try await activateMode("leader")
        XCTAssertEqual(delays, [1500])
        XCTAssertEqual(TrayMenuModel.shared.modePresentation?.initial, "L")
        try await activateMode("leader")
        fires[0]()
        await Task.yield()
        XCTAssertEqual(activeMode, "leader")
        fires[1]()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(activeMode, "main")
        XCTAssertNil(TrayMenuModel.shared.modePresentation)
    }

    func testAcceptedConcurrentBindingsProtectWholeSequenceAndRearmOnce() async throws {
        var fires: [@MainActor () -> Void] = []
        let session = runtime.hotkeys.modeSession
        session.schedule = { _, fire in fires.append(fire); return {} }
        try await activateMode("leader")
        let a = try XCTUnwrap(session.begin(expected: session.generation))
        let b = try XCTUnwrap(session.begin(expected: session.generation))
        fires[0]() // emulate a canceled callback racing dispatch
        await Task.yield()
        // A canceled deadline must not exit even though the activation generation is unchanged.
        XCTAssertEqual(activeMode, "leader")
        session.finish(a)
        XCTAssertEqual(fires.count, 1)
        session.finish(b)
        XCTAssertEqual(fires.count, 2)
        try await activateMode("main")
        session.finish(b)
        XCTAssertEqual(fires.count, 2)
    }

    func testSuspensionResetAndMainCancelTimersAndIndicator() async throws {
        var fires: [@MainActor () -> Void] = []
        runtime.hotkeys.modeSession.schedule = { _, fire in fires.append(fire); return {} }
        try await activateMode("leader")
        setHotkeysSuspended(true)
        XCTAssertNil(TrayMenuModel.shared.modePresentation)
        fires[0]()
        await Task.yield()
        XCTAssertEqual(activeMode, "leader")
        setHotkeysSuspended(false)
        XCTAssertEqual(fires.count, 2)
        XCTAssertNotNil(TrayMenuModel.shared.modePresentation)
        resetHotKeys()
        fires[1]()
        await Task.yield()
        XCTAssertEqual(activeMode, "leader")
    }

    func testEnteringModeInsideAcceptedSequenceWaitsForItsCompletion() async throws {
        var count = 0
        let session = runtime.hotkeys.modeSession
        session.schedule = { _, _ in count += 1; return {} }
        try await activateMode("main")
        let accepted = try XCTUnwrap(session.begin(expected: session.generation))
        try await activateMode("leader")
        XCTAssertEqual(count, 0, "The rest of the entry binding may still be running")
        session.finish(accepted)
        XCTAssertEqual(count, 1)
    }

    func testReusedCarbonShortcutResolvesCurrentModeAndRejectsQueuedOldSession() async throws {
        config = parseConfig("""
        [mode.main.binding]
        h = 'mode leader'
        [mode.leader]
        timeout-ms = 1500
        [mode.leader.binding]
        h = 'mode main'
        """).config
        runtime.hotkeys.modeSession.schedule = { _, _ in {} }
        try await activateMode("main")
        let key = try XCTUnwrap(runtime.hotkeys.hotkeys.values.first)
        try await activateMode("leader")
        key.keyDownHandler?()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(activeMode, "main", "The shared Carbon registration must run leader's command")
        key.keyDownHandler?()
        try await activateMode("main") // re-entry invalidates the queued main callback
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(activeMode, "main")
    }

    func testModeHookReentryInvalidatesPreviousDeadline() async throws {
        var fires: [@MainActor () -> Void] = []
        runtime.hotkeys.modeSession.schedule = { _, fire in fires.append(fire); return {} }
        guard case .cmd(let backToMain) = parseCommand("mode main") else { return XCTFail() }
        config.onModeChanged = [backToMain]
        try await activateMode("leader")
        XCTAssertEqual(activeMode, "main")
        XCTAssertEqual(fires.count, 1)
        fires[0]()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(activeMode, "main")
        XCTAssertNil(TrayMenuModel.shared.modePresentation)
    }

    func testExplicitBindingFailureStillRearmsDeadline() async throws {
        var count = 0
        runtime.hotkeys.modeSession.schedule = { _, _ in count += 1; return {} }
        try await activateMode("leader")
        guard case .cmd(let missing) = parseCommand("focus --window-id 999999999") else { return XCTFail() }
        config.modes["leader"]?.bindings["h"] = HotkeyBinding([], .h, [missing], descriptionWithKeyNotation: "h")
        guard case .cmd(let command) = parseCommand("trigger-binding h --mode leader") else { return XCTFail() }
        let result = try await command.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 1) // missing window is an actual command failure
        XCTAssertEqual(count, 2)
        XCTAssertEqual(activeMode, "leader")
    }

    func testMainNeverArmsAndRuntimeOwnersAreIndependent() async throws {
        var count = 0
        runtime.hotkeys.modeSession.schedule = { _, _ in count += 1; return {} }
        config.modes["main"]?.timeoutMs = 100
        config.modes["main"]?.showIndicator = true
        try await activateMode("main")
        XCTAssertEqual(count, 0)
        XCTAssertNil(TrayMenuModel.shared.modePresentation)
        let original = runtime
        let other = WinMuxRuntime(config: config)
        try await other.withValue {
            other.hotkeys.modeSession.schedule = { _, _ in count += 1; return {} }
            try await activateMode("leader")
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(original.hotkeys.activeMode, "main")
        XCTAssertEqual(other.hotkeys.activeMode, "leader")
        other.hotkeys.modeSession.invalidate()
        updateModePresentation()
    }

    func testModeColorAdjustsExtremeColorsForBothMenuAppearances() {
        for hex in ["#000000", "#FFFFFF", "#5E9EFF"] {
            var mode = Mode.zero
            mode.indicatorColor = hex
            let presentation = ModePresentation(name: "navigation", mode: mode)
            for dark in [false, true] {
                let color = presentation.color(dark: dark, increasedContrast: true).usingColorSpace(.sRGB)!
                func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
                let l = 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
                let b: CGFloat = dark ? 0.015 : 0.9
                XCTAssertGreaterThanOrEqual((max(l, b) + 0.05) / (min(l, b) + 0.05), 7)
            }
        }
    }

    func testUnicodeInitialAndMetadataSurviveShortcutEdit() {
        for (name, initial) in [(" navigation", "N"), ("ßmode", "S"), ("👩🏽‍💻 tools", "👩🏽‍💻"), (" ", "?")] {
            XCTAssertEqual(ModePresentation(name: name, mode: .zero).initial, initial)
        }
        let original = "[mode.leader]\ntimeout-ms = 1500\nshow-indicator = true\nindicator-color = '#5E9EFF'\n[mode.leader.binding]\nh = 'focus left'\n"
        let edited = updateModeBindingConfig(in: original, modeName: "leader", managedCommands: ["focus left"], assignments: ["j": "focus down"])
        let mode = parseConfig(edited).config.modes["leader"]
        XCTAssertEqual(mode?.timeoutMs, 1500)
        XCTAssertEqual(mode?.indicatorColor, "#5E9EFF")
        XCTAssertEqual(mode?.showIndicator, true)
    }

    func testPublicStateAndHookContextContainSameModeWithoutNativeReads() async throws {
        try await activateMode("leader")
        let snapshot = publicStateSnapshot()
        guard case .object(let mode) = snapshot.state["mode"] else { return XCTFail("Missing mode") }
        XCTAssertEqual(mode["name"], .string("leader"))
        XCTAssertEqual(mode["initial"], .string("L"))
        let env = hookEnvironment(event: "mode-changed", previousMode: "main").asMap
        XCTAssertEqual(env["WINMUX_MODE"], "leader")
        XCTAssertEqual(env["WINMUX_PREV_MODE"], "main")
        XCTAssertEqual(env["WINMUX_MODE_COLOR"], { if case .string(let color) = mode["resolvedColor"] { return color }; return "" }())
        let previous = runtime.publicState.revision
        requestPublicStateUpdate()
        XCTAssertGreaterThan(publicStateSnapshot().revision, previous)
        let other = WinMuxRuntime()
        XCTAssertNotEqual(other.publicState.instanceId, snapshot.instanceId)
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(PublicStateEnvelope.self, from: encoded), snapshot)
    }

    func testStateDuringTransactionUsesCommittedSnapshot() {
        let before = publicStateSnapshot()
        runtime.publicState.transactionDepth += 1
        runtime.publicState.paletteVisible = true
        requestPublicStateUpdate()
        XCTAssertEqual(publicStateSnapshot(), before)
        runtime.publicState.transactionDepth -= 1
        XCTAssertNotEqual(publicStateSnapshot().state, before.state)
    }
}

@MainActor final class PublicStateSubscriptionTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testInitialThenOrderedUpdatesAndReconnect() async throws {
        var messages: [PublicStateEnvelope] = []
        let writer = SubscriberEventWriter(send: { data in
            messages.append(try! JSONDecoder().decode(PublicStateEnvelope.self, from: data)); return true
        }, disconnect: {})
        let id = registerSubscriber(events: [.stateChanged], writer: writer, sendInitial: true)
        defer { unregisterSubscriber(id) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(messages.count, 1)
        runtime.publicState.paletteVisible = true
        requestPublicStateUpdate()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(messages.count, 2)
        XCTAssertGreaterThan(messages[1].revision, messages[0].revision)
        XCTAssertEqual(messages[1].instanceId, messages[0].instanceId)
        requestPublicStateUpdate() // no observable change: no redundant event
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(messages.count, 2)
        var reconnected: [Data] = []
        let second = registerSubscriber(events: [.stateChanged], writer: SubscriberEventWriter(send: { reconnected.append($0); return true }, disconnect: {}), sendInitial: true)
        defer { unregisterSubscriber(second) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(reconnected.count, 1)
        XCTAssertEqual(try JSONDecoder().decode(PublicStateEnvelope.self, from: reconnected[0]).state, messages[1].state)
    }

    func testSubscriptionArrivingMidTransactionWaitsForSettledSnapshotEvenIfUnchanged() async throws {
        let before = publicStateSnapshot()
        runtime.publicState.lastPublished = before.state
        runtime.publicState.transactionDepth = 1
        var messages: [Data] = []
        let id = registerSubscriber(events: [.stateChanged], writer: SubscriberEventWriter(send: { messages.append($0); return true }, disconnect: {}), sendInitial: true)
        defer { unregisterSubscriber(id) }
        requestPublicStateUpdate()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(messages.isEmpty)
        runtime.publicState.transactionDepth = 0
        requestPublicStateUpdate()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(try JSONDecoder().decode(PublicStateEnvelope.self, from: messages[0]).state, before.state)
    }

    func testNoInitialAndLegacyModeEventShapeRemainUnchanged() async throws {
        var messages: [Data] = []
        let id = registerSubscriber(events: [.modeChanged, .stateChanged], writer: SubscriberEventWriter(send: { messages.append($0); return true }, disconnect: {}), sendInitial: false)
        defer { unregisterSubscriber(id) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(messages.isEmpty)
        broadcastEvent(.modeChanged(mode: "leader"))
        for _ in 0..<10 { await Task.yield() }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: messages[0]) as? [String: String])
        XCTAssertEqual(object, ["_event": "mode-changed", "mode": "leader"])
    }

    func testSnapshotQueryDoesNotReadNativeStateLayoutOrReconcile() async throws {
        let workspace = Workspace.get(byName: "1")
        let window = TestWindow.new(id: 91091, parent: workspace.rootTilingContainer)
        let untouched = Workspace.get(byName: "empty-query-sentinel")
        var args = StateCmdArgs(rawArgs: [])
        args.json = true
        let command = StateCommand(args: args)
        let result = try await runCommandSession(.socketServer(args), .forceRun, isQuery: command.isQuery, shouldSchedulePostRefresh: false) {
            try await command.run(.defaultEnv, .emptyStdin)
        }
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(window.nativeStateFetchCount, 0)
        XCTAssertNil(window.lastAppliedLayoutPhysicalRect)
        XCTAssertTrue(Workspace.existing(byName: untouched.name) === untouched)
        XCTAssertNil(runtime.publicState.publicationTask)
    }

    func testDirectUISessionInvalidatesStructuralCache() async throws {
        let before = publicStateSnapshot()
        try await runLightSession(.menuBarButton, .forceRun, shouldSchedulePostRefresh: false) {
            _ = TestWindow.new(id: 91093, parent: focus.workspace.rootTilingContainer)
        }
        XCTAssertNotEqual(publicStateSnapshot().state["windows"], before.state["windows"])
    }

    func testStateRemainsAvailableWhenManagementIsDisabled() async throws {
        TrayMenuModel.shared.isEnabled = false
        defer { TrayMenuModel.shared.isEnabled = true }
        let command = StateCommand(args: StateCmdArgs(rawArgs: []))
        XCTAssertNotNil(RunSessionGuard.isServerEnabled(orIsEnableCommand: command))
        XCTAssertNil(RunSessionGuard.isServerEnabled(orIsEnableCommand: ModeCommand(args: ModeCmdArgs(rawArgs: []))))
        let result = try await command.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        guard case .object(let state) = publicStateSnapshot().state["runtime"] else { return XCTFail() }
        XCTAssertEqual(state["enabled"], .bool(false))
    }

    func testStructureChangesUnknownNativeStateAndConfigMetadataSerialize() async throws {
        let workspace = Workspace.get(byName: "named")
        let window = TestWindow.new(id: 91092, parent: workspace.rootTilingContainer)
        requestPublicStateUpdate(structural: true)
        let before = publicStateSnapshot()
        guard case .array(let windows) = before.state["windows"], case .object(let info) = windows.first else { return XCTFail() }
        XCTAssertEqual(info["nativeMinimized"], .null)
        window.closeAxWindow()
        requestPublicStateUpdate(structural: true)
        let after = publicStateSnapshot()
        XCTAssertNotEqual(before.state["windows"], after.state["windows"])
        XCTAssertEqual(after.instanceId, before.instanceId)
    }
}
