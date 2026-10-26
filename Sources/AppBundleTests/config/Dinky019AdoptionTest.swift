@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class Dinky019AdoptionTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws { setUpWorkspacesForTests() }

    func testModifierAliasesUseExistingChordIdentityAndSideFilter() throws {
        let aliases = parseConfig("""
            [modifiers]
            alt = 'left'
            [mode.main.binding]
            hyper-1 = 'workspace 1'
            meh-2 = 'workspace 2'
            """)
        XCTAssertTrue(aliases.errors.isEmpty, "\(aliases.errors)")
        let bindings = try XCTUnwrap(aliases.config.modes["main"]).bindings.values
        XCTAssertEqual(bindings.count, 2)
        let hyper = try parseBinding("hyper-1", .emptyRoot, config.keyMapping.resolve()).get()
        let expanded = try parseBinding("alt-ctrl-cmd-shift-1", .emptyRoot, config.keyMapping.resolve()).get()
        XCTAssertEqual(hyper.0, expanded.0)
        XCTAssertEqual(hyper.1, expanded.1)
        XCTAssertTrue(aliases.config.modifierSides.restricts(hyper.0))
        for (alias, full) in [("hyper", "alt-ctrl-cmd-shift"), ("meh", "alt-ctrl-shift")] {
            let duplicate = parseConfig("[mode.main.binding]\n\(alias)-1 = 'workspace 1'\n\(full)-1 = 'workspace 2'")
            XCTAssertTrue(duplicate.errors.contains { $0.description.contains("redeclaration") })
        }
        XCTAssertFalse(parseConfig("[mode.main.binding]\nsuper-1 = 'workspace 1'").errors.isEmpty)
    }

    func testBundleIdRegexIsCaseInsensitiveAndConjunctiveWithExactId() async throws {
        let text = """
            [[on-window-detected]]
            if.app-id-regex = '^BOBKO\\.WinMux\\.'
            if.app-id = 'bobko.WinMux.test-app'
            run = 'layout tiling'
            """
        let parsed = parseConfig(text)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        var callback = try XCTUnwrap(parsed.config.onWindowDetected.first)
        let window = TestWindow.new(id: 99001, parent: focus.workspace.rootTilingContainer)
        let matches = try await callback.matches(window)
        XCTAssertTrue(matches)
        callback.matcher.appId = "another.app"
        let wrongExact = try await callback.matches(window)
        XCTAssertFalse(wrongExact)
        callback.matcher.appId = nil
        callback.matcher.appIdRegex = try Regex("^com\\.jetbrains\\.")
        let wrongRegex = try await callback.matches(window)
        XCTAssertFalse(wrongRegex)
        XCTAssertFalse(parseConfig("[[on-window-detected]]\nif.app-id-regex = '['\nrun = 'layout tiling'").errors.isEmpty)
    }

    func testRuleEditorPreservesAndEditsBundleIdRegex() throws {
        let block = """
            [[on-window-detected]]
            # family of applications
            if.app-id-regex = '^com\\.jetbrains\\.'
            run = ['layout tiling']
            """
        let original = try SettingsRuleDraft(block: block)
        XCTAssertEqual(original.appIdRegex, "^com\\.jetbrains\\.")
        var changed = original
        changed.appIdRegex = "^com\\.apple\\."
        let edited = try SettingsRuleDocument.editing(block, edits: changed.edits(from: original))
        XCTAssertTrue(edited.contains("# family of applications"))
        XCTAssertEqual(try SettingsRuleDraft(block: edited).appIdRegex, changed.appIdRegex)
        XCTAssertTrue(parseConfig(edited).errors.isEmpty)
        XCTAssertTrue(SettingsRuleRow(id: 0, block: edited).matches.contains(changed.appIdRegex))
    }

    func testHookPathKeepsConfiguredVariablesAndHandlesFinderEnvironment() {
        let finder = execEnvironment([:], context: ["WINMUX_DISPLAYS": "2"], cliDirectory: "/Applications/WinMuxX.app/Contents/Helpers")
        XCTAssertEqual(finder["PATH"], "/Applications/WinMuxX.app/Contents/Helpers:/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(finder["WINMUX_DISPLAYS"], "2")
        let custom = execEnvironment(["PATH": "/custom/bin", "KEEP": "yes"], context: [:], cliDirectory: "/bundle/Helpers")
        XCTAssertEqual(custom["PATH"], "/bundle/Helpers:/custom/bin")
        XCTAssertEqual(custom["KEEP"], "yes")
        XCTAssertEqual(execEnvironment(["PATH": "/custom/bin"], context: [:], cliDirectory: nil), ["PATH": "/custom/bin"])
    }

    func testDisplayHookIgnoresDuplicateAndGeometryOnlyNotifications() {
        var tracker = DisplayChangeTracker()
        XCTAssertNil(tracker.update(["laptop"]))
        XCTAssertEqual(tracker.update(["laptop", "external"]), ["WINMUX_DISPLAYS": "2", "WINMUX_PREV_DISPLAYS": "1"])
        XCTAssertNil(tracker.update(["external", "laptop"]))
        XCTAssertEqual(tracker.update(["laptop", "replacement"]), ["WINMUX_DISPLAYS": "2", "WINMUX_PREV_DISPLAYS": "2"])
        XCTAssertEqual(tracker.update(["laptop"]), ["WINMUX_DISPLAYS": "1", "WINMUX_PREV_DISPLAYS": "2"])
        XCTAssertTrue(parseConfig("on-display-changed = 'exec-and-forget echo $WINMUX_DISPLAYS'").errors.isEmpty)
    }

    func testWorkspaceArrangementsInheritBaseAndPickMostSpecificPattern() throws {
        let (main, external) = displays()
        let parsed = parseConfig("""
            [workspace.1]
            layout = 'dwindle'
            orientation = 'horizontal'
            [workspace.1.display.'Samsung']
            layout = 'scrolling'
            [workspace.1.display.'Samsung Ultra']
            layout = 'master'
            orientation = 'vertical'
            """)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        let rule = try XCTUnwrap(parsed.config.workspaceLayouts["1"])
        XCTAssertEqual(rule.settings(on: main), WorkspaceLayoutSettings(layout: .dwindle, orientation: .horizontal))
        XCTAssertEqual(rule.settings(on: external), WorkspaceLayoutSettings(layout: .master, orientation: .vertical))
        let partial = parseConfig("[workspace.1]\nlayout = 'dwindle'\n[workspace.1.display.secondary]\norientation = 'vertical'")
        XCTAssertEqual(partial.config.workspaceLayouts["1"]?.settings(on: external), WorkspaceLayoutSettings(layout: .dwindle, orientation: .vertical))
        for invalid in ["workspace = []", "[workspace.1]\nlayout = 'fixed'", "[workspace.1]\nrows = 2", "[workspace.1.display.'[']\nlayout = 'tiles'", "[workspace.1]\ndisplay = 5", "[workspace.1]\norientation = 'diagonal'"] {
            XCTAssertFalse(parseConfig(invalid).errors.isEmpty, invalid)
        }
    }

    func testConfiguredLayoutChangesOnlyOnPolicyChangeAndDoesNotMoveWorkspace() throws {
        let (main, external) = displays()
        config.workspaceLayouts = parseConfig("""
            [workspace.1]
            layout = 'dwindle'
            [workspace.1.display.'Samsung']
            layout = 'master'
            """).config.workspaceLayouts
        let workspace = Workspace.get(byName: "1")
        _ = main.setActiveWorkspace(workspace)
        let window = TestWindow.new(id: 99002, parent: workspace.rootTilingContainer)
        let initialGroupLayout = workspace.rootTilingContainer.layout
        workspace.applyConfiguredLayout()
        XCTAssertEqual(workspace.rootTilingContainer.layout, initialGroupLayout)
        XCTAssertEqual(workspace.arrangement, .dwindle)
        workspace.rootTilingContainer.layout = .tiles
        workspace.applyConfiguredLayout()
        XCTAssertEqual(workspace.rootTilingContainer.layout, .tiles, "Manual layout survives refresh")
        XCTAssertEqual(workspace.workspaceMonitor.name, main.name)
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(workspace, targetMonitor: external))
        workspace.applyConfiguredLayout()
        XCTAssertEqual(workspace.arrangement, .master)
        XCTAssertTrue(window.nodeWorkspace === workspace)
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(workspace, targetMonitor: main))
        workspace.applyConfiguredLayout()
        XCTAssertEqual(workspace.arrangement, .dwindle)
        XCTAssertEqual(workspace.rootTilingContainer.layout, .tiles)
        config.workspaceLayouts = [:]
        workspace.applyConfiguredLayout()
        XCTAssertEqual(workspace.arrangement, .dwindle)
    }

    func testCommandsSucceedAtAnEdgeButKeepExplicitFailAndFloatingErrors() async throws {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 99003, parent: workspace.rootTilingContainer)
        _ = window.focusWindow()
        for command in ["move --boundaries-action stop left", "join-with left", "resize height +10"] {
            let result = try await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode, 0, command + result.stderr.joined())
        }
        let failure = try await parseCommand("move --boundaries-action fail left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(failure.exitCode, 1)
        window.bind(to: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        let floating = try await parseCommand("resize width +10").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(floating.exitCode, 1)
        let floatingJoin = try await parseCommand("join-with left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(floatingJoin.exitCode, 1)
    }

    func testDisablingClearsDragStateImmediately() async throws {
        TrayMenuModel.shared.isEnabled = true
        currentlyManipulatedWithMouseWindowId = 99004
        setCurrentMouseManipulationKind(.move)
        WindowMouseInteractionDriver.shared.moveSession = .init(windowId: 99004, subject: .window, detachOrigin: .window, startedInSidebar: false)
        let result = try await parseCommand("enable off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNil(currentlyManipulatedWithMouseWindowId)
        XCTAssertNil(WindowMouseInteractionDriver.shared.moveSession)
        XCTAssertFalse(isMouseManipulationActive)
    }

    func testThirtyLiveNavigationBoundariesDoNotScheduleRedundantRefreshes() async throws {
        TrayMenuModel.shared.isEnabled = true
        var scheduled = 0
        setScheduledRefreshOverrideForTests { _, _ in scheduled += 1 }
        let main = mainMonitor
        let first = focus.workspace
        let second = Workspace.get(byName: "swipe-destination")
        _ = TestWindow.new(id: 99005, parent: first.rootTilingContainer)
        _ = TestWindow.new(id: 99006, parent: second.rootTilingContainer)
        for index in 0..<30 {
            let target = index.isMultiple(of: 2) ? second : first
            let result = try await WorkspaceSwipeDependencies.live.navigate { activateWorkspaceForUser(target, on: main) }
            XCTAssertTrue(result)
            try await waitForScheduledRefreshForTests()
            XCTAssertTrue(focus.workspace === target)
        }
        XCTAssertEqual(scheduled, 0)
    }

    func testSwipeKeepsInterruptedNativeRefreshEvenWithoutItsOwnFollowup() async throws {
        TrayMenuModel.shared.isEnabled = true
        let started = expectation(description: "Native creation refresh began")
        var events: [String] = []
        setScheduledRefreshOverrideForTests { event, _ in
            events.append(event.description)
            if events.count == 1 {
                started.fulfill()
                try await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        let creation = RefreshSessionEvent.ax(kAXWindowCreatedNotification as String)
        scheduleRefreshSession(creation)
        await fulfillment(of: [started], timeout: 2)
        _ = try await WorkspaceSwipeDependencies.live.navigate { true }
        try await waitForScheduledRefreshForTests()
        XCTAssertEqual(events, [creation.description, creation.description])
    }

    func testGlobalLayoutReloadDoesNotOverrideExplicitWorkspacePolicy() {
        config.workspaceLayouts = parseConfig("[workspace.1]\nlayout = 'scrolling'\norientation = 'vertical'").config.workspaceLayouts
        let workspace = Workspace.get(byName: "1")
        workspace.applyConfiguredLayout()
        config.defaultRootContainerLayout = .dwindle
        _ = applyDwindleToExistingTiledWorkspaces()
        workspace.applyConfiguredLayout()
        XCTAssertEqual(workspace.arrangement, .scrolling)
        XCTAssertEqual(workspace.rootTilingContainer.orientation, .h)
    }

    func testSettledDisplayHookSurvivesCoalescingIntoAnotherNativeEvent() async throws {
        _ = displays()
        TrayMenuModel.shared.isEnabled = true
        runtime.displays.changes.seed(["previous-display"])
        runtime.displays.displayHookPending = true
        let called = expectation(description: "Display callback after native refresh")
        var calls = 0
        config.onDisplayChanged = [DisplayHookSpy { env in
            calls += 1
            XCTAssertEqual(env.asMap[WINMUX_DISPLAYS], "2")
            XCTAssertEqual(env.asMap[WINMUX_PREV_DISPLAYS], "1")
            XCTAssertEqual(Workspace.all.filter(\.isVisible).count, 2)
            called.fulfill()
        }]
        setBlockingRefreshOverridesForTests(refresh: {}, normalizeLayoutReason: {})
        try await runRefreshSessionBlocking(.ax(kAXWindowCreatedNotification as String))
        await fulfillment(of: [called], timeout: 2)
        await runtime.displays.displayChangeTask?.value
        XCTAssertFalse(runtime.displays.displayHookPending)
        try await runRefreshSessionBlocking(.ax(kAXWindowCreatedNotification as String))
        XCTAssertEqual(calls, 1)
        XCTAssertNil(CmdEnv.defaultEnv.asMap[WINMUX_DISPLAYS], "Counts do not leak into ordinary commands")
    }

    private func displays() -> (Monitor, Monitor) {
        let mainRect = Rect(topLeftX: 0, topLeftY: 0, width: 1600, height: 1000)
        let externalRect = Rect(topLeftX: 1600, topLeftY: 0, width: 3440, height: 1440)
        let main = WorkspaceNamingTestMonitor(monitorAppKitNsScreenScreensId: 1, name: "Built-in", rect: mainRect, visibleRect: mainRect, isMain: true)
        let external = WorkspaceNamingTestMonitor(monitorAppKitNsScreenScreensId: 2, name: "Samsung Ultrawide", rect: externalRect, visibleRect: externalRect, isMain: false)
        setMonitorsForTests([main, external])
        return (main, external)
    }
}

private struct DisplayHookSpy: Command {
    let args = ListModesCmdArgs(rawArgs: [])
    let shouldResetClosedWindowsCache = false
    let canSkipPostCommandRefresh = true
    let observe: @MainActor @Sendable (CmdEnv) -> Void

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        observe(env)
        return true
    }
}
