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
        XCTAssertEqual(config.modes["leader"]?.exitOnUnboundKey, false)
        XCTAssertEqual(parseConfig("[mode.nav]\nexit-on-unbound-key = true").config.modes["nav"]?.exitOnUnboundKey, true)
        for body in ["timeout-ms = -1", "timeout-ms = 60001", "timeout-ms = true", "timeout-ms = 1.5", "show-indicator = 'yes'", "exit-on-unbound-key = 'yes'", "indicator-color = '#fff'"] {
            XCTAssertFalse(parseConfig("[mode.main]\n[mode.test]\n" + body).errors.isEmpty, body)
        }
        for timeout in [0, 60000] { XCTAssertTrue(parseConfig("[mode.main]\n[mode.test]\ntimeout-ms = \(timeout)").errors.isEmpty) }
    }

    func testUnboundExitImmediatelyDisablesOldBindingsAndCancelsDeadline() async throws {
        var fires: [@MainActor () -> Void] = []
        runtime.hotkeys.modeSession.schedule = { _, fire in fires.append(fire); return {} }
        config.modes["leader"]?.exitOnUnboundKey = true
        try await activateMode("leader")
        let key = try XCTUnwrap(runtime.hotkeys.hotkeys.values.first)
        XCTAssertTrue(key.isEnabled)
        let oldGeneration = runtime.hotkeys.modeSession.generation
        XCTAssertTrue(exitModeForUnboundKey(keyCode: 12, flags: [])) // Q is unassigned.
        XCTAssertFalse(key.isEnabled)
        XCTAssertNotEqual(runtime.hotkeys.modeSession.generation, oldGeneration)
        XCTAssertFalse(exitModeForUnboundKey(keyCode: 12, flags: []), "Queue only one exit")
        fires[0]()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(activeMode, "main")
        XCTAssertFalse(runtime.hotkeys.pendingUnboundModeExit)
        XCTAssertNil(TrayMenuModel.shared.modePresentation)
    }

    func testUnboundExitPreservesBoundKeysAndUsesExactModifiers() async throws {
        config.modes["leader"]?.exitOnUnboundKey = true
        try await activateMode("leader")
        let h = try XCTUnwrap(config.modes["leader"]?.bindings.values.first { $0.descriptionWithKeyNotation == "h" })
        XCTAssertFalse(exitModeForUnboundKey(keyCode: Int64(h.keyCode.carbonKeyCode), flags: [.capsLock, .function]))
        XCTAssertEqual(activeMode, "leader")
        XCTAssertTrue(exitModeForUnboundKey(keyCode: Int64(h.keyCode.carbonKeyCode), flags: [.command]))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(activeMode, "main")
    }

    func testUnboundKeyCannotTriggerMainUntilItsRelease() async throws {
        let parsed = parseConfig("""
        [mode.main.binding]
        q = 'mode leader'
        [mode.leader]
        exit-on-unbound-key = true
        [mode.leader.binding]
        h = 'focus left'
        """)
        XCTAssertTrue(parsed.errors.isEmpty)
        config = parsed.config
        try await activateMode("main")
        let mainKey = try XCTUnwrap(runtime.hotkeys.hotkeys.values.first)
        try await activateMode("leader")
        XCTAssertTrue(exitModeForUnboundKey(keyCode: 12, flags: []))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(activeMode, "main")
        XCTAssertFalse(mainKey.isEnabled, "The original Q must reach the app, including repeats")
        mainKey.keyDownHandler?()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(activeMode, "main")
        finishUnboundKeyPassThrough(keyCode: 0) // An unrelated key-up cannot release Q's gate.
        XCTAssertFalse(mainKey.isEnabled)
        finishUnboundKeyPassThrough(keyCode: 12)
        XCTAssertTrue(mainKey.isEnabled)
        mainKey.keyDownHandler?()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(activeMode, "leader", "The next Q can use main's binding normally")
    }

    func testUnboundReleaseBeforeActivationDoesNotReenableOldModeAndTapRecoveryClearsGate() async throws {
        config.modes["leader"]?.exitOnUnboundKey = true
        try await activateMode("main")
        try await activateMode("leader")
        XCTAssertTrue(exitModeForUnboundKey(keyCode: 12, flags: []))
        finishUnboundKeyPassThrough(keyCode: 12)
        XCTAssertTrue(runtime.hotkeys.hotkeys.values.allSatisfy { !$0.isEnabled })
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(activeMode, "main")
        try await activateMode("leader")
        XCTAssertTrue(exitModeForUnboundKey(keyCode: 12, flags: []))
        for _ in 0..<30 { await Task.yield() }
        finishUnboundKeyPassThrough(keyCode: nil)
        XCTAssertNil(runtime.hotkeys.unboundPassthroughKeyCode)
        XCTAssertTrue(runtime.hotkeys.hotkeys.values.contains { $0.isEnabled })
    }

    func testUnboundExitIsOptInAndIgnoredWhileDisabledSuspendedOrInMain() async throws {
        try await activateMode("leader")
        XCTAssertFalse(exitModeForUnboundKey(keyCode: 12, flags: []))
        config.modes["leader"]?.exitOnUnboundKey = true
        setHotkeysSuspended(true)
        XCTAssertFalse(exitModeForUnboundKey(keyCode: 12, flags: []))
        setHotkeysSuspended(false)
        TrayMenuModel.shared.isEnabled = false
        XCTAssertFalse(exitModeForUnboundKey(keyCode: 12, flags: []))
        TrayMenuModel.shared.isEnabled = true
        config.modes["main"]?.exitOnUnboundKey = true
        try await activateMode("main")
        XCTAssertFalse(exitModeForUnboundKey(keyCode: 12, flags: []))
    }

    func testPendingUnboundExitCannotOverrideNewModeActivationOrSuspension() async throws {
        config.modes["leader"]?.exitOnUnboundKey = true
        try await activateMode("leader")
        XCTAssertTrue(exitModeForUnboundKey(keyCode: 12, flags: []))
        try await activateMode("leader")
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(activeMode, "leader")
        XCTAssertTrue(exitModeForUnboundKey(keyCode: 12, flags: []))
        setHotkeysSuspended(true)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(activeMode, "leader")
        XCTAssertFalse(runtime.hotkeys.pendingUnboundModeExit)
    }

    func testUnboundExitPreservesSequencesAndHonorsModifierSides() async throws {
        let parsed = parseConfig("""
        [modifiers]
        alt = 'left'
        [mode.main.binding]
        [mode.leader]
        exit-on-unbound-key = true
        [mode.leader.binding]
        esc-q = 'mode main'
        alt-h = 'focus left'
        """)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        config = parsed.config
        try await activateMode("leader")
        let sequence = try XCTUnwrap(config.modes["leader"]?.sequenceBindings.values.first)
        XCTAssertFalse(exitModeForUnboundKey(keyCode: Int64(sequence.prefix.carbonKeyCode), flags: []))
        noteSequencePrefixKeyPressed(sequence.prefix)
        XCTAssertFalse(exitModeForUnboundKey(keyCode: Int64(sequence.key.carbonKeyCode), flags: []))
        let h = try XCTUnwrap(config.modes["leader"]?.bindings.values.first)
        let left: NSEvent.ModifierFlags = [.option, TapModifierKey.leftAlt.deviceSpecificModifierFlag]
        let right: NSEvent.ModifierFlags = [.option, TapModifierKey.rightAlt.deviceSpecificModifierFlag]
        XCTAssertFalse(exitModeForUnboundKey(keyCode: Int64(h.keyCode.carbonKeyCode), flags: left))
        XCTAssertTrue(exitModeForUnboundKey(keyCode: Int64(h.keyCode.carbonKeyCode), flags: right))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(activeMode, "main")
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

    func testRepeatedAndReentrantMenuAppearanceNotificationsDoNotRepaint() {
        var gate = MenuBarAppearanceGate()
        var paints = 0
        func notify(_ scheme: NSAppearance.Name) {
            guard gate.accept(scheme) else { return }
            paints += 1
            // Rendering may emit a notification before the observer returns.
            XCTAssertFalse(gate.accept(scheme))
        }
        for _ in 0..<1000 { notify(.aqua) }
        XCTAssertEqual(paints, 1)
        for _ in 0..<1000 { notify(.darkAqua) }
        XCTAssertEqual(paints, 2)
        notify(.aqua)
        XCTAssertEqual(paints, 3)
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
        let original = "[mode.leader]\ntimeout-ms = 1500\nshow-indicator = true\nexit-on-unbound-key = true\nindicator-color = '#5E9EFF'\n[mode.leader.binding]\nh = 'focus left'\n"
        let edited = updateModeBindingConfig(in: original, modeName: "leader", managedCommands: ["focus left"], assignments: ["j": "focus down"])
        let mode = parseConfig(edited).config.modes["leader"]
        XCTAssertEqual(mode?.timeoutMs, 1500)
        XCTAssertEqual(mode?.indicatorColor, "#5E9EFF")
        XCTAssertEqual(mode?.showIndicator, true)
        XCTAssertEqual(mode?.exitOnUnboundKey, true)
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
