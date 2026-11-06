@testable import AppBundle
import AppKit
import Common
import HotKey
import XCTest

@MainActor
final class ActionMenuTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func command(_ script: String) throws -> any Command {
        guard case .cmd(let command) = parseCommand(script) else {
            XCTFail("Invalid command: \(script)")
            throw NSError(domain: "ActionMenuTest", code: 1)
        }
        return command
    }

    private func mode(_ text: String, name: String = "main") throws -> Mode {
        let (parsed, errors) = parseConfig("shortcuts-preset = 'none'\n" + text)
        XCTAssertTrue(errors.isEmpty, errors.descriptions.joined(separator: "\n"))
        return try XCTUnwrap(parsed.modes[name])
    }

    func testAllCatalogActionsParseAndHaveUniqueCommandsAndIds() throws {
        let actions = buildShortcutSections().flatMap(\.actions)
        XCTAssertEqual(Set(actions.map(\.id)).count, actions.count)
        XCTAssertEqual(Set(actions.map(\.canonicalCommand)).count, actions.count)
        for action in actions { _ = try command(action.commandScript) }
    }

    func testSingleBindingUsesNativeShortcut() throws {
        var bindings = ActionMenuBindings(mode: try mode("[mode.main.binding]\nalt-left = 'focus left'"))
        let matches = bindings.bindings(for: try command("focus left"))
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].keyEquivalent, String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        XCTAssertEqual(matches[0].modifiers, .option)
        XCTAssertTrue(bindings.unshown.isEmpty)
    }

    func testOnlyExactConfiguredLayoutGetsShortcut() throws {
        var bindings = ActionMenuBindings(mode: try mode("""
        [mode.main.binding]
        alt-space = 'workspace-layout dwindle'
        alt-shift-t = 'layout floating tiling'
        """))
        XCTAssertEqual(bindings.bindings(for: try command("workspace-layout dwindle")).map(\.notation), ["alt-space"])
        XCTAssertEqual(bindings.bindings(for: try command("layout floating tiling")).map(\.notation), ["alt-shift-t"])
        for script in ["layout h_tiles", "layout v_tiles", "layout tab-group", "layout horizontal vertical"] {
            XCTAssertTrue(bindings.bindings(for: try command(script)).isEmpty, script)
        }
    }

    func testRenderedUnconfiguredLayoutsHaveBlankShortcuts() throws {
        let previousMode = activeMode
        defer { activeMode = previousMode }
        activeMode = "main"
        config.modes["main"] = try mode("""
        [mode.main.binding]
        alt-space = 'workspace-layout dwindle'
        alt-shift-t = 'layout floating tiling'
        """)
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        XCTAssertEqual(try XCTUnwrap(menu.items.first { $0.title == "Dwindle" }).keyEquivalent, " ")
        for arrangement in WorkspaceLayoutName.allCases {
            let item = try XCTUnwrap(menu.items.first { $0.title == arrangement.rawValue.capitalized })
            XCTAssertNotNil(item.image, "\(arrangement) shows its picture")
            XCTAssertEqual(item.state, focus.workspace.arrangement == arrangement ? .on : .off)
        }
        let layout = try submenu("Container Layout", in: try submenu("Commands", in: menu))
        XCTAssertEqual(try XCTUnwrap(layout.items.first { $0.title == "Toggle Floating" }).keyEquivalent, "t")
        for title in ["Tiles", "Tabbed", "Accordion", "Horizontal", "Vertical"] {
            let item = try XCTUnwrap(layout.items.first { $0.title == title })
            XCTAssertEqual(item.title, title)
            XCTAssertEqual(item.keyEquivalent, "", title)
        }
    }

    func testMenuHeaderNamesWorkspaceOnce() throws {
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        let header = try XCTUnwrap(menu.items.first).title
        XCTAssertEqual(header, "WinMuxX · \(workspaceDisplayName(focus.workspace.name))")
        XCTAssertFalse(header.contains("Workspace Workspace"), header)
    }

    func testAboutItemSitsAboveSettingsAndCreditsTheFork() throws {
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        let about = try XCTUnwrap(titles.firstIndex(of: "About WinMuxX"))
        XCTAssertEqual(titles[about + 1], "Settings…")
        XCTAssertTrue(menu.items[about].isEnabled)
        let credits = aboutPanelCredits()
        XCTAssertTrue(credits.string.contains("WinMux by Zimeng Xiong"), credits.string)
        let link = credits.attribute(.link, at: credits.length - 1, effectiveRange: nil) as? URL
        XCTAssertEqual(link?.absoluteString, "https://github.com/gfavaro/WinMuxX")
    }

    func testEssentialMenuOmitsRareCommandsRatherThanNestingThem() throws {
        let previousMode = activeMode
        defer { activeMode = previousMode }
        activeMode = mainModeId
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        for title in ["Dwindle", "Master", "Scrolling", "Retile", "Balance Sizes", "Fullscreen", "No Peek", "Borders",
                      "Focus Follows Pointer", "Commands", "About WinMuxX", "Settings…", "Enabled", "Quit WinMuxX"] {
            XCTAssertTrue(titles.contains(title), title)
        }
        for title in ["Workspaces", "Focus", "Move Window", "Join With", "Resize", "Reload Config", "Clear Saved Minimum Sizes…"] {
            XCTAssertFalse(titles.contains(title), "\(title) is not at the top level")
        }
        XCTAssertEqual(menu.items.filter { $0.submenu != nil }.map(\.title), ["Commands"])
        let commands = try submenu("Commands", in: menu)
        for title in ["Workspaces", "Focus", "Move Window", "Join With", "Resize", "Container Layout", "Reload Config"] {
            XCTAssertTrue(commands.items.contains { $0.title == title }, title)
        }
        XCTAssertFalse(titles.contains("Mode: main"))
        func descendants(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(descendants) ?? []) }
        }
        let allTitles = descendants(menu).map(\.title)
        for title in ["Advanced", "Projects", "Utilities", "Other Key Bindings", "Bring Here", "Copy Version", "Open Config", "Diagnostics…", "Close Other Windows…", "New Opposite Container", "Next Tab"] {
            XCTAssertFalse(allTitles.contains(title), title)
        }
        let workspaces = try submenu("Workspaces", in: commands)
        XCTAssertNotNil(workspaces.items.first { $0.title == "Move and Follow" }?.submenu)
        XCTAssertNotNil(workspaces.items.first { $0.title == "Move Window to" }?.submenu)
        if sortedMonitors.count == 1 { XCTAssertFalse(commands.items.contains { $0.title == "Display" }) }
    }

    func testTopLevelShowsOnlyTheCurrentLayoutsItemsAndConfigToggles() throws {
        let workspace = focus.workspace
        let previousArrangement = workspace.arrangement
        let previousBorders = config.windowBorders.enabled
        let previousPointerFocus = config.focusFollowsMouse
        defer {
            workspace.arrangement = previousArrangement
            config.windowBorders.enabled = previousBorders
            config.focusFollowsMouse = previousPointerFocus
        }
        config.windowBorders.enabled = true
        config.focusFollowsMouse = false
        let menu = NSMenu()
        let controller = NativeActionMenu()
        workspace.arrangement = .master
        controller.menuNeedsUpdate(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "Swap with Master" })
        XCTAssertFalse(menu.items.contains { $0.title == "Center Column" })
        XCTAssertEqual(menu.items.first { $0.title == "Borders" }?.state, .on)
        XCTAssertEqual(menu.items.first { $0.title == "Focus Follows Pointer" }?.state, .off)
        workspace.arrangement = .scrolling
        controller.menuNeedsUpdate(menu)
        XCTAssertFalse(menu.items.contains { $0.title == "Swap with Master" })
        for title in ["Center Column", "Show Minimap", "Cycle Column Width", "Pin Column Left", "Pin Column Right"] {
            XCTAssertTrue(menu.items.contains { $0.title == title }, title)
        }
        workspace.arrangement = .dwindle
        controller.menuNeedsUpdate(menu)
        XCTAssertFalse(menu.items.contains { $0.title == "Swap with Master" || $0.title == "Center Column" })
    }

    private func submenu(_ title: String, in menu: NSMenu) throws -> NSMenu {
        try XCTUnwrap(menu.items.first { $0.title == title }?.submenu, title)
    }

    func testMultipleBindingsAreAllClaimed() throws {
        var bindings = ActionMenuBindings(mode: try mode("[mode.main.binding]\nalt-left = 'focus left'\nalt-h = 'focus left'"))
        XCTAssertEqual(bindings.bindings(for: try command("focus left")).count, 2)
        XCTAssertTrue(bindings.unshown.isEmpty)
    }

    func testMultiCommandBindingNeverLabelsOneAction() throws {
        var bindings = ActionMenuBindings(mode: try mode("[mode.main.binding]\nalt-h = ['focus left', 'mode main']"))
        XCTAssertTrue(bindings.bindings(for: try command("focus left")).isEmpty)
        XCTAssertEqual(bindings.unshown.count, 1)
        XCTAssertEqual(bindings.unshown[0].commands.count, 2)
    }

    func testTapAndSequenceBindingsHaveTextLabelsAndRemainExecutable() throws {
        var bindings = ActionMenuBindings(mode: try mode("""
        [mode.main.binding]
        esc-h = 'focus left'
        [mode.main.binding-tap]
        left-alt = 'focus left'
        """))
        let matches = bindings.bindings(for: try command("focus left"))
        XCTAssertEqual(matches.count, 2)
        XCTAssertTrue(matches.allSatisfy { $0.keyEquivalent == nil && $0.commands.count == 1 })
        XCTAssertTrue(matches.contains { $0.notation.hasPrefix("Tap ") })
        XCTAssertTrue(matches.contains { $0.notation.hasPrefix("Sequence ") })
        XCTAssertTrue(bindings.unshown.isEmpty)
    }

    func testCustomExecIsPreservedInOtherBindings() throws {
        let bindings = ActionMenuBindings(mode: try mode("[mode.main.binding]\nalt-enter = 'exec-and-forget open -a Ghostty'"))
        XCTAssertEqual(bindings.unshown.count, 1)
        XCTAssertTrue(bindings.unshown[0].commands[0] is ExecAndForgetCommand)
    }

    func testCurrentModeDoesNotLeakMainBindings() throws {
        let current = try mode("""
        [mode.main.binding]
        alt-left = 'focus left'
        [mode.grouping.binding]
        left = ['stack-with left', 'mode main']
        """, name: "grouping")
        var bindings = ActionMenuBindings(mode: current)
        XCTAssertTrue(bindings.bindings(for: try command("focus left")).isEmpty)
        XCTAssertEqual(bindings.unshown.map(\.notation), ["left"])
    }

    func testNewSnapshotReflectsReloadedBindings() throws {
        let old = try mode("[mode.main.binding]\nalt-left = 'focus left'")
        let new = try mode("[mode.main.binding]\nctrl-left = 'focus left'")
        XCTAssertEqual(ActionMenuBindings(mode: old).entries[0].modifiers, .option)
        XCTAssertEqual(ActionMenuBindings(mode: new).entries[0].modifiers, .control)
    }

    func testNoModeStillAllowsCatalogWithoutShortcuts() throws {
        var bindings = ActionMenuBindings(mode: nil)
        XCTAssertTrue(bindings.bindings(for: try command("workspace-layout dwindle")).isEmpty)
        XCTAssertTrue(bindings.unshown.isEmpty)
    }

    func testWindowRequirementsDistinguishWorkspaceAndWindowActions() throws {
        for script in ["focus left", "workspace-layout dwindle", "fullscreen", "move-node-to-workspace 2"] {
            XCTAssertTrue(menuCommandRequiresWindow(try command(script)))
        }
        for script in ["workspace 2", "mode main", "enable toggle", "reload-config", "focus-monitor main"] {
            XCTAssertFalse(menuCommandRequiresWindow(try command(script)))
        }
    }

    func testNativeKeyEquivalents() {
        XCTAssertEqual(menuKeyEquivalent(.a), "a")
        XCTAssertEqual(menuKeyEquivalent(.space), " ")
        XCTAssertEqual(menuKeyEquivalent(.f12), String(UnicodeScalar(NSF1FunctionKey + 11)!))
        XCTAssertEqual(menuKeyEquivalent(.leftBracket), "[")
        XCTAssertEqual(menuKeyEquivalent(.pageUp), String(UnicodeScalar(NSPageUpFunctionKey)!))
        XCTAssertEqual(menuKeyEquivalent(.forwardDelete), String(UnicodeScalar(NSDeleteFunctionKey)!))
    }

    func testPotentialConflictsAreDeduplicatedAndExcludeWinMux() {
        XCTAssertEqual(otherTilingManagers(["com.brnbw.dinky", "com.brnbw.dinky", "com.knollsoft.Rectangle", "com.winmux.app", "com.apple.finder"]), ["Dinky", "Rectangle"])
        XCTAssertTrue(otherTilingManagers([]).isEmpty)
    }

    func testProcessConflictsIncludeDaemonsAndIgnoreUnrelatedProcesses() {
        XCTAssertEqual(otherTilingManagerProcesses(["AeroSpace", "aerospace", "yabai", "KiwiDesk", "Dinky", "WinMux", "Dock"]), ["AeroSpace", "Dinky", "KiwiDesk", "yabai"])
        XCTAssertTrue(otherTilingManagerProcesses([]).isEmpty)
    }

    func testDiagnosticsReportsLoadedConfigurationAndDoesNotChangeLayout() async {
        let originalConfig = config
        let originalUrl = configUrl
        let originalShortcutHealth = TrayMenuModel.shared.shortcutHealth
        TrayMenuModel.shared.shortcutHealth = .unavailable
        defer { TrayMenuModel.shared.shortcutHealth = originalShortcutHealth }
        let report = await buildDiagnosticsReport()
        XCTAssertTrue(report.contains("loaded: \(configUrl.path)"))
        XCTAssertTrue(report.contains("default root layout:"))
        XCTAssertTrue(report.contains("Permissions:"))
        XCTAssertTrue(report.contains("keyboard shortcuts: WARNING"))
        XCTAssertTrue(report.contains("Per-app AX latency"))
        XCTAssertEqual(config.defaultRootContainerLayout, originalConfig.defaultRootContainerLayout)
        XCTAssertEqual(config.modes, originalConfig.modes)
        XCTAssertEqual(configUrl, originalUrl)
    }

    func testMenuWithoutWindowDisablesLayoutButAllowsWorkspaceAndSettings() throws {
        let previousEnabled = TrayMenuModel.shared.isEnabled
        defer { TrayMenuModel.shared.isEnabled = previousEnabled }
        TrayMenuModel.shared.isEnabled = true
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        XCTAssertFalse(try XCTUnwrap(menu.items.first { $0.title == "Dwindle" }).isEnabled)
        let workspaces = try submenu("Workspaces", in: try submenu("Commands", in: menu))
        XCTAssertTrue(try XCTUnwrap(workspaces.items.first { $0.title == "Next" }).isEnabled)
        XCTAssertTrue(try XCTUnwrap(menu.items.first { $0.title == "Settings…" }).isEnabled)
    }

    func testMenuShowsShortcutWarningWhenSideFilteredHandlingIsUnavailable() throws {
        let previousEnabled = TrayMenuModel.shared.isEnabled
        let previousHealth = TrayMenuModel.shared.shortcutHealth
        defer {
            TrayMenuModel.shared.isEnabled = previousEnabled
            TrayMenuModel.shared.shortcutHealth = previousHealth
        }
        TrayMenuModel.shared.isEnabled = true
        TrayMenuModel.shared.shortcutHealth = .unavailable
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "⚠ Some keyboard shortcuts are unavailable" })
        XCTAssertTrue(menu.items.contains { $0.title == "View shortcut diagnostics…" })
    }

    func testDisabledMenuKeepsEssentialControlsAvailable() throws {
        let previousEnabled = TrayMenuModel.shared.isEnabled
        defer { TrayMenuModel.shared.isEnabled = previousEnabled }
        TrayMenuModel.shared.isEnabled = false
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        for title in ["Enabled", "Settings…", "Quit WinMuxX"] {
            XCTAssertTrue(try XCTUnwrap(menu.items.first { $0.title == title }).isEnabled, title)
        }
        let commands = try submenu("Commands", in: menu)
        XCTAssertTrue(try XCTUnwrap(commands.items.first { $0.title == "Reload Config" }).isEnabled)
        let workspaces = try submenu("Workspaces", in: commands)
        XCTAssertFalse(try XCTUnwrap(workspaces.items.first { $0.title == "Next" }).isEnabled)
    }

    func testMenuReflectsModeAndConfigurationOnEveryOpening() throws {
        let oldMode = activeMode
        defer { activeMode = oldMode }
        config.modes["main"] = try mode("[mode.main.binding]\nalt-space = 'workspace-layout dwindle'")
        activeMode = "main"
        let menu = NSMenu()
        let controller = NativeActionMenu()
        controller.menuNeedsUpdate(menu)
        XCTAssertEqual(try XCTUnwrap(menu.items.first { $0.title == "Dwindle" }).keyEquivalent, " ")
        activeMode = "grouping"
        config.modes["grouping"] = .zero
        controller.menuNeedsUpdate(menu)
        XCTAssertEqual(try XCTUnwrap(menu.items.first { $0.title == "Dwindle" }).keyEquivalent, "")
        XCTAssertTrue(menu.items.contains { $0.title == "Mode: grouping" })
    }

    func testDiagnosticsIncludesReloadFailureWithoutChangingEffectiveConfig() async {
        let oldError = lastConfigReloadError
        defer { lastConfigReloadError = oldError }
        lastConfigReloadError = "Invalid layout at config line 15"
        let originalLayout = config.defaultRootContainerLayout
        let report = await buildDiagnosticsReport()
        XCTAssertTrue(report.contains("last reload error: Invalid layout at config line 15"))
        XCTAssertEqual(config.defaultRootContainerLayout, originalLayout)
    }

    func testDiagnosticsIdentifiesInvalidFileAndKeepsEffectiveConfig() async {
        let originalUrl = configUrl
        defer { configUrl = originalUrl }
        configUrl = projectRoot.appendingPathComponent("Sources/AppBundle/command/impl/DoctorCommand.swift")
        let originalLayout = config.defaultRootContainerLayout
        let originalModes = config.modes
        let report = await buildDiagnosticsReport()
        XCTAssertTrue(report.contains("file validation: ERROR (running config retained)"))
        XCTAssertEqual(config.defaultRootContainerLayout, originalLayout)
        XCTAssertEqual(config.modes, originalModes)
    }

    func testDiagnosticsIdentifiesMissingFile() async {
        let originalUrl = configUrl
        defer { configUrl = originalUrl }
        configUrl = projectRoot.appendingPathComponent("missing-\(UUID().uuidString).toml")
        let report = await buildDiagnosticsReport()
        XCTAssertTrue(report.contains("file is missing"))
    }

    func testDiagnosticsReportWhatTheInstallerChecks() async {
        let report = await buildDiagnosticsReport()
        XCTAssertTrue(report.contains("  accessibility: "))
        XCTAssertTrue(report.contains("  screen capture: "))
        XCTAssertTrue(report.contains("loaded: \(configUrl.path)"))
    }

    func testWorkspaceMenuIsScopedToActiveProject() {
        let project = createWorkspaceProject()
        let other = Workspace.get(byName: "other-project")
        other.assignProject(project.id)
        TestWindow.new(id: 1401, parent: other.rootTilingContainer)
        XCTAssertFalse(menuWorkspaceTargets().contains { $0.workspace == other })
        XCTAssertTrue(menuWorkspaceTargets().allSatisfy { $0.workspace.projectId == focus.workspace.projectId })
    }

    func testWorkspaceMenuCommandFocusesVisibleWorkspaceWithoutMovingIt() async throws {
        let displays = (0..<2).map { index in
            let rect = Rect(topLeftX: Double(index * 1920), topLeftY: 0, width: 1920, height: 1080)
            return TestMonitor(monitorAppKitNsScreenScreensId: index + 1, name: "Display\(index + 1)", rect: rect, visibleRect: rect, isMain: index == 0)
        }
        setMonitorsForTests(displays)
        defer { setMonitorsForTests(nil) }
        let first = Workspace.get(byName: "1")
        let second = Workspace.get(byName: "2")
        TestWindow.new(id: 1411, parent: first.rootTilingContainer).markAsMostRecentChild()
        TestWindow.new(id: 1412, parent: second.rootTilingContainer).markAsMostRecentChild()
        XCTAssertTrue(displays[0].setActiveWorkspace(first))
        XCTAssertTrue(displays[1].setActiveWorkspace(second))
        XCTAssertTrue(first.focusWorkspace())
        let originalWindow = focus.windowOrNil
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        XCTAssertEqual(focus.windowOrNil, originalWindow, "Building a menu must not steal focus")
        let workspaceMenu = try submenu("Workspaces", in: try submenu("Commands", in: menu))
        let item = try XCTUnwrap(workspaceMenu.items.first { $0.title == workspaceDisplayName(second.name) })
        let payload = try XCTUnwrap(item.representedObject as? MenuCommandPayload)
        let result = try await payload.commands.runCmdSeq(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined(separator: "\n"))
        XCTAssertEqual(displays[0].activeWorkspace, first)
        XCTAssertEqual(displays[1].activeWorkspace, second)
        XCTAssertEqual(focus.workspace, second)
    }
}
