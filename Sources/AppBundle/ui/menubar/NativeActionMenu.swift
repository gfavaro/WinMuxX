import AppKit
import Combine
import Common
import NativeSpaces

/// AppKit can notify effectiveAppearance again while a status button is rendered.
/// Accept only actual scheme changes so rendering cannot feed its own observer.
struct MenuBarAppearanceGate {
    private var previous: NSAppearance.Name?
    mutating func accept(_ name: NSAppearance.Name) -> Bool {
        guard previous != name else { return false }
        previous = name
        return true
    }
}

@MainActor
public func installNativeMenuBar(checkForUpdates: (() -> Void)? = nil) {
    NativeActionMenu.shared.install(checkForUpdates: checkForUpdates)
}

@MainActor
final class NativeActionMenu: NSObject, NSMenuDelegate {
    static let shared = NativeActionMenu()
    private var statusItem: NSStatusItem?
    private var nativeMenu: NSMenu?
    private var observation: AnyCancellable?
    private var accessibilityObservation: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var checkForUpdates: (() -> Void)?
    private var bindings = ActionMenuBindings(mode: nil)
    private var appearanceGate = MenuBarAppearanceGate()
    private var lastModePresentation: ModePresentation?
    private var lastIconState: (enabled: Bool, appearance: MenuBarIconAppearance, indicator: MenuBarIndicator, text: String, name: String, arrangement: WorkspaceLayoutName)?
    private var capturedRuleTarget: QuickFloatingRuleTarget?

    func install(checkForUpdates: (() -> Void)?) {
        guard statusItem == nil else { return }
        self.checkForUpdates = checkForUpdates
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        nativeMenu = menu
        item.menu = menu
        statusItem = item
        if let button = item.button {
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.initial, .new]) { button, _ in
                Task { @MainActor in
                    let match = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
                    guard self.appearanceGate.accept(match) else { return }
                    WorkspaceSidebarPanel.menuBarColorScheme = match == .aqua ? .light : .dark
                    self.lastIconState = nil
                    self.updateIcon()
                    requestPublicStateUpdate()
                    WorkspaceSidebarPanel.refreshWallpaperContrast()
                }
            }
        }
        accessibilityObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastIconState = nil
                self?.updateIcon()
                requestPublicStateUpdate()
            }
        }
        updateIcon()
        observation = TrayMenuModel.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    func openMenu() {
        guard let button = statusItem?.button, let nativeMenu else { return }
        nativeMenu.update()
        nativeMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
    }

    func containsStatusItem(point: NSPoint) -> Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
    }

    private func updateIcon() {
        if runtime.workspaceBackend.kind == .native {
            let model = TrayMenuModel.shared
            if model.menuBarConfiguration.indicator == .workspace, Int(model.menuBarWorkspaceIndicator) != nil {
                statusItem?.length = NSStatusItem.variableLength
                statusItem?.button?.image = nil
                statusItem?.button?.attributedTitle = NSAttributedString(string: model.menuBarWorkspaceIndicator,
                    attributes: [.foregroundColor: NSColor.labelColor])
                statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
            } else {
                statusItem?.length = NSStatusItem.squareLength
                statusItem?.button?.attributedTitle = NSAttributedString(string: "")
                statusItem?.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Native Spaces")
            }
            statusItem?.button?.toolTip = "WinMuxX · \(model.menuBarWorkspaceName)"
            statusItem?.button?.setAccessibilityLabel("WinMuxX, \(model.menuBarWorkspaceName)")
            return
        }
        let model = TrayMenuModel.shared
        let state = (enabled: model.isEnabled, appearance: model.menuBarConfiguration.iconAppearance, indicator: model.menuBarConfiguration.indicator, text: model.menuBarWorkspaceIndicator, name: model.menuBarWorkspaceName, arrangement: model.menuBarWorkspaceArrangement)
        if let previous = lastIconState, previous.enabled == state.enabled, previous.appearance == state.appearance, previous.indicator == state.indicator, previous.text == state.text, previous.name == state.name, previous.arrangement == state.arrangement, lastModePresentation == model.modePresentation { return }
        lastIconState = state
        lastModePresentation = model.modePresentation
        let mode = model.isEnabled ? model.modePresentation : nil
        let dark = statusItem?.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let color = mode?.color(dark: dark, increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        let modeDescription = mode.map { " · Mode: \($0.name)" + ($0.escapeReturnsToMain ? " · Esc to exit" : "") } ?? ""
        let arrangementName = state.arrangement.rawValue.capitalized
        let arrangementDescription = " · \(arrangementName) layout"
        if model.isEnabled && state.indicator == .workspace {
            statusItem?.length = NSStatusItem.variableLength
            statusItem?.button?.image = nil
            let title = NSMutableAttributedString(string: state.text, attributes: [.foregroundColor: NSColor.labelColor])
            if let mode, let color { title.append(NSAttributedString(string: " | \(mode.initial)", attributes: [.foregroundColor: color])) }
            statusItem?.button?.attributedTitle = title
            statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
            statusItem?.button?.toolTip = "WinMux · \(state.name) · Focused display" + arrangementDescription + modeDescription
            statusItem?.button?.setAccessibilityLabel("WinMux, workspace \(state.name), focused display, \(arrangementName) layout" + modeDescription)
            return
        }
        statusItem?.length = NSStatusItem.squareLength
        statusItem?.button?.attributedTitle = NSAttributedString(string: "")
        statusItem?.button?.setAccessibilityLabel(model.isEnabled ? "WinMux, \(arrangementName) layout" + modeDescription : "WinMux disabled")
        let image = menuBarIconImage(
            enabled: model.isEnabled,
            arrangement: state.arrangement,
            appearance: model.menuBarConfiguration.iconAppearance,
            keyboardTint: color,
        )
        image?.size = NSSize(width: 18, height: 18)
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = "WinMuxX" + arrangementDescription + modeDescription
    }

    func menuWillOpen(_ menu: NSMenu) {
        WorkspaceControlsPanelController.shared.dismiss()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        if runtime.workspaceBackend.kind == .native { return buildNativeMenu(menu) }
        bindings = ActionMenuBindings(mode: activeMode.flatMap { config.modes[$0] })
        capturedRuleTarget = focus.windowOrNil.flatMap { window -> QuickFloatingRuleTarget? in
            guard let app = window as? MacWindow, let bundleId = app.macApp.rawAppBundleId else { return nil }
            return QuickFloatingRuleTarget(window: app, focus: focus, bundleId: bundleId,
                pid: app.macApp.pid, launchDate: app.macApp.nsApp.launchDate, workspaceId: focus.workspace.id)
        }
        menu.addItem(NSMenuItem(title: "WinMuxX · Workspace \(workspaceDisplayName(focus.workspace.name))", action: nil, keyEquivalent: ""))
        if activeMode != mainModeId {
            menu.addItem(NSMenuItem(title: "Mode: \(activeMode ?? "none")", action: nil, keyEquivalent: ""))
        }
        if TrayMenuModel.shared.shortcutHealth == .unavailable {
            menu.addItem(NSMenuItem(title: "⚠ Some keyboard shortcuts are unavailable", action: nil, keyEquivalent: ""))
            menu.addItem(callbackItem("View shortcut diagnostics…", #selector(openDiagnostics)))
        }
        let conflicts = runningOtherWindowManagers()
        if !conflicts.isEmpty {
            menu.addItem(NSMenuItem(title: "⚠ Other window managers: \(conflicts.joined(separator: ", "))", action: nil, keyEquivalent: ""))
            menu.addItem(callbackItem("Window management may conflict — view diagnostics…", #selector(openDiagnostics)))
        }
        menu.addItem(.separator())
        addSubmenu("Workspaces", to: menu) { workspacesMenu in
            addCommand("Previous", script: "workspace prev", to: workspacesMenu)
            addCommand("Next", script: "workspace next", to: workspacesMenu)
            addCommand("Back and Forth", script: "workspace-back-and-forth", to: workspacesMenu)
            for (workspace, target) in menuWorkspaceTargets() {
                let item = addCommand(workspaceDisplayName(workspace.name), args: ["workspace", target], to: workspacesMenu)
                item?.state = workspace == focus.workspace ? .on : .off
            }
            workspacesMenu.addItem(.separator())
            addSubmenu("Move and Follow", to: workspacesMenu) { submenu in
                addCommand("Previous", script: "move-node-to-workspace --focus-follows-window prev", to: submenu)
                addCommand("Next", script: "move-node-to-workspace --focus-follows-window next", to: submenu)
                for (workspace, target) in menuWorkspaceTargets() {
                    addCommand(workspaceDisplayName(workspace.name), args: ["move-node-to-workspace", "--focus-follows-window", target], to: submenu)
                }
            }
            addSubmenu("Move Window to", to: workspacesMenu) { submenu in
                addCommand("Previous", script: "move-node-to-workspace prev", to: submenu)
                addCommand("Next", script: "move-node-to-workspace next", to: submenu)
                for (workspace, target) in menuWorkspaceTargets() {
                    addCommand(workspaceDisplayName(workspace.name), args: ["move-node-to-workspace", target], to: submenu)
                }
            }
        }
        menu.addItem(.separator())
        for (title, command) in [("Focus", "focus"), ("Move Window", "move"), ("Join With", "join-with")] {
            addSubmenu(title, to: menu) { submenu in
                for direction in ["left", "down", "up", "right"] {
                    addCommand(direction.capitalized, script: "\(command) \(direction)", to: submenu)
                }
            }
        }
        addSubmenu("Resize", to: menu) { submenu in
            for (title, script) in [("Wider", "resize width +50"), ("Narrower", "resize width -50"),
                                    ("Taller", "resize height +50"), ("Shorter", "resize height -50")] {
                addCommand(title, script: script, to: submenu)
            }
        }
        addSubmenu("Layout", to: menu) { submenu in
            for (title, script) in [("Tiles", "layout tiles"),
                                    ("Tabbed", "layout tab-group"), ("Accordion", "layout accordion")] {
                addCommand(title, script: script, to: submenu)
            }
            submenu.addItem(.separator())
            addCommand("Dwindle", script: "workspace-layout dwindle", to: submenu)
            addCommand("Master", script: "workspace-layout master", to: submenu)
            addCommand("Scrolling", script: "workspace-layout scrolling", to: submenu)
            submenu.addItem(.separator())
            addCommand("Horizontal", script: "layout horizontal", to: submenu)
            addCommand("Vertical", script: "layout vertical", to: submenu)
            submenu.addItem(.separator())
            addCommand("Swap with Master", script: "swap-with-master", to: submenu)
            addCommand("Center Scrolling Column", script: "scrolling-center", to: submenu)
            addCommand("Show Scrolling Minimap", script: "scrolling-minimap", to: submenu)
            addCommand("Cycle Scrolling Width", script: "scrolling-width next", to: submenu)
            addCommand("Toggle Floating", script: "layout floating tiling", to: submenu)
        }
        addCommand("Fullscreen", script: "fullscreen", to: menu)
        if capturedRuleTarget != nil {
            menu.addItem(callbackItem("Always Float This App…", #selector(alwaysFloatApp)))
            menu.addItem(callbackItem("Create Floating Rule for This Window…", #selector(floatThisWindow)))
        }
        addCommand("Balance Sizes", script: "balance-sizes", to: menu)
        if sortedMonitors.count > 1 {
            addSubmenu("Display", to: menu) { submenu in
                addCommand("Focus Previous", script: "focus-monitor prev", to: submenu)
                addCommand("Focus Next", script: "focus-monitor next", to: submenu)
                submenu.addItem(.separator())
                for (index, monitor) in sortedMonitors.enumerated() {
                    addCommand("Move Window to \(monitor.name)", args: ["move-node-to-monitor", String(index + 1)], to: submenu)
                }
            }
        }
        if config.modes.count > 1 {
            addSubmenu("Mode", to: menu) { submenu in
                for mode in config.modes.keys.sorted() {
                    let item = addCommand(mode, args: ["mode", mode], to: submenu)
                    item?.state = mode == activeMode ? .on : .off
                }
            }
        }
        menu.addItem(.separator())
        menu.addItem(callbackItem("Workspace Controls…", #selector(openWorkspaceControls)))
        addCommand("Reload Config", script: "reload-config", to: menu, requiresWindow: false, allowDisabled: true)
        if !PersistedAppMinimums.shared.isEmpty || MacWindow.allWindows.contains(where: { !$0.learnedMinimum.isEmpty }) {
            menu.addItem(callbackItem("Clear Saved Minimum Sizes…", #selector(resetMinimumSizes)))
        }
        menu.addItem(callbackItem("Settings…", #selector(openSettings)))
        let enabled = addCommand("Enabled", script: "enable toggle", to: menu, requiresWindow: false, allowDisabled: true)
        enabled?.state = TrayMenuModel.shared.isEnabled ? .on : .off
        let recoverableCount = WindowRecoveryController.shared.recoverableEntries.count
        if recoverableCount > 0 {
            let item = callbackItem("Recover \(recoverableCount) Windows from Previous Session…", #selector(recoverWindows))
            item.isEnabled = !WindowRecoveryController.shared.isRecovering
            menu.addItem(item)
        }
        menu.addItem(callbackItem("Quit WinMuxX", #selector(quit)))
    }

    /// Desktops come from macOS; only commands the native backend runs are offered.
    private func buildNativeMenu(_ menu: NSMenu) {
        let backend = runtime.workspaceBackend
        bindings = ActionMenuBindings(mode: activeMode.flatMap { config.modes[$0] })
        let displays = nativeObservedDisplays() ?? []
        let focusedDisplay = focus.workspace.workspaceMonitor.displayUUID
        let current = displays.first { $0.identifier == focusedDisplay } ?? displays.first
        let number = current.flatMap { NativeSpaceNavigation.activeDesktopNumber(on: $0.identifier, in: displays) }
        let title = current == nil ? "Native Spaces" : number.map { nativeDesktopDisplayName($0) } ?? "Fullscreen App"
        menu.addItem(NSMenuItem(title: "WinMuxX · \(title)", action: nil, keyEquivalent: ""))
        if case .unavailable(let reason) = backend.observation?.inventory.status {
            menu.addItem(NSMenuItem(title: "⚠ Native Spaces unavailable: \(reason)", action: nil, keyEquivalent: ""))
        } else if !backend.nativeTilingEnabled {
            menu.addItem(NSMenuItem(title: "Tiling off (observation only)", action: nil, keyEquivalent: ""))
        } else if !backend.nativeTiling.ready {
            menu.addItem(NSMenuItem(title: "Tiling paused: \(backend.nativeTiling.status)", action: nil, keyEquivalent: ""))
        }
        if activeMode != mainModeId {
            menu.addItem(NSMenuItem(title: "Mode: \(activeMode ?? "none")", action: nil, keyEquivalent: ""))
        }
        func add(_ title: String, _ script: String, to menu: NSMenu) -> NSMenuItem? {
            guard case .cmd(let command) = parseCommand(script), backend.accepts(command) else { return nil }
            return addCommand(title, command: command, to: menu, requiresWindow: command is WorkspaceCommand ? false : nil)
        }

        menu.addItem(.separator())
        var desktop = 0
        for display in displays {
            if displays.count > 1 {
                let name = sortedMonitors.first { $0.displayUUID == display.identifier }?.name ?? "Display"
                let header = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
            }
            for space in display.spaces {
                guard space.isDesktop else {
                    let item = NSMenuItem(title: "Fullscreen App", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    item.state = space.id == display.activeSpaceID ? .on : .off
                    menu.addItem(item)
                    continue
                }
                desktop += 1
                let item = add(nativeDesktopDisplayName(desktop), "workspace \(desktop)", to: menu)
                item?.state = space.id == display.activeSpaceID ? .on : .off
            }
        }
        _ = add("Previous Desktop", "workspace prev", to: menu)
        _ = add("Next Desktop", "workspace next", to: menu)

        if backend.nativeTilingEnabled {
            menu.addItem(.separator())
            if NativeWindowSpaceMover.isAvailable {
                addSubmenu("Move Window to Desktop", to: menu) { submenu in
                    for number in 1...max(desktop, 1) {
                        _ = add(nativeDesktopDisplayName(number), "move-node-to-workspace \(number)", to: submenu)
                    }
                }
            }
            for (title, command) in [("Focus", "focus"), ("Move Window", "move")] {
                addSubmenu(title, to: menu) { submenu in
                    for direction in ["left", "down", "up", "right"] { _ = add(direction.capitalized, "\(command) \(direction)", to: submenu) }
                }
            }
            addSubmenu("Resize", to: menu) { submenu in
                for (title, script) in [("Wider", "resize width +50"), ("Narrower", "resize width -50"),
                                        ("Taller", "resize height +50"), ("Shorter", "resize height -50")] {
                    _ = add(title, script, to: submenu)
                }
            }
            addSubmenu("Layout", to: menu) { submenu in
                let arrangement = focus.workspace.arrangement
                add("Dwindle", "workspace-layout dwindle", to: submenu)?.state = arrangement == .dwindle ? .on : .off
                add("Master", "workspace-layout master", to: submenu)?.state = arrangement == .master ? .on : .off
                submenu.addItem(.separator())
                _ = add("Horizontal", "layout horizontal", to: submenu)
                _ = add("Vertical", "layout vertical", to: submenu)
                submenu.addItem(.separator())
                _ = add("Swap with Master", "swap-with-master", to: submenu)
                _ = add("Toggle Floating", "layout floating tiling", to: submenu)
            }
            _ = add("Fullscreen", "fullscreen", to: menu)
            _ = add("Balance Sizes", "balance-sizes", to: menu)
        }
        if config.modes.count > 1, backend.nativeTilingEnabled {
            addSubmenu("Mode", to: menu) { submenu in
                for mode in config.modes.keys.sorted() {
                    add(mode, "mode \(mode)", to: submenu)?.state = mode == activeMode ? .on : .off
                }
            }
        }

        menu.addItem(.separator())
        addCommand("Reload Config", script: "reload-config", to: menu, requiresWindow: false, allowDisabled: true)
        menu.addItem(callbackItem("Open Config…", #selector(openConfig)))
        menu.addItem(callbackItem("Refresh Desktops", #selector(refreshNativeSpaces)))
        menu.addItem(callbackItem("Diagnostics…", #selector(openDiagnostics)))
        menu.addItem(callbackItem("Quit WinMuxX", #selector(quit)))
    }

    private func addSubmenu(_ title: String, to menu: NSMenu, build: (NSMenu) -> Void) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        build(submenu)
        item.submenu = submenu
        menu.addItem(item)
    }

    @discardableResult
    private func addCommand(_ title: String, script: String, to menu: NSMenu, requiresWindow: Bool? = nil, allowDisabled: Bool = false) -> NSMenuItem? {
        guard case .cmd(let command) = parseCommand(script) else { return nil }
        return addCommand(title, command: command, to: menu, requiresWindow: requiresWindow, allowDisabled: allowDisabled)
    }

    @discardableResult
    private func addCommand(_ title: String, args: [String], to menu: NSMenu) -> NSMenuItem? {
        guard case .cmd(let command) = parseCommand(args) else { return nil }
        return addCommand(title, command: command, to: menu)
    }

    private func addCommand(_ title: String, command: any Command, to menu: NSMenu, requiresWindow: Bool? = nil, allowDisabled: Bool = false) -> NSMenuItem {
        let item = commandItem(title, commands: [command])
        let needsWindow = requiresWindow ?? menuCommandRequiresWindow(command)
        item.isEnabled = (allowDisabled || TrayMenuModel.shared.isEnabled) && (!needsWindow || focus.windowOrNil != nil)
        applyBindings(bindings.bindings(for: command), to: item)
        menu.addItem(item)
        return item
    }

    private func commandItem(_ title: String, commands: [any Command]) -> NSMenuItem {
        let displayTitle = title.count > 140 ? String(title.prefix(140)) + "…" : title
        let item = callbackItem(displayTitle, #selector(runCommand(_:)))
        item.representedObject = MenuCommandPayload(commands: commands)
        item.toolTip = commands.prettyDescription
        item.isEnabled = TrayMenuModel.shared.isEnabled && (!commands.contains(where: menuCommandRequiresWindow) || focus.windowOrNil != nil)
        return item
    }

    private func applyBindings(_ matches: [ActionMenuBinding], to item: NSMenuItem) {
        if matches.count == 1, let binding = matches.first, let key = binding.keyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = binding.modifiers
        } else if !matches.isEmpty {
            item.title += "  [\(matches.map(\.notation).joined(separator: ", "))]"
        }
    }

    private func callbackItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuCommandPayload else { return }
        var environment = CmdEnv.defaultEnv
        if payload.commands.count == 1, payload.commands.first is CloseAllWindowsButCurrentCommand {
            environment = environment.withFocus(focus)
            let alert = NSAlert()
            alert.messageText = "Close other windows in this workspace?"
            alert.informativeText = "Applications may ask you to save unsaved changes. The focused window will stay open."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Close Other Windows")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        let commandEnvironment = environment
        Task {
            do {
                guard let token = RunSessionGuard.isServerEnabled(orIsEnableCommand: payload.commands.first) ?? (payload.commands.first is ReloadConfigCommand ? .forceRun : nil) else { return }
                try await runLightSession(.menuBarButton, token, shouldSchedulePostRefresh: !payload.commands.canSkipPostCommandRefresh) {
                    let result = try await payload.commands.runCmdSeq(commandEnvironment, .emptyStdin)
                    if result.exitCode != 0 {
                        MessageModel.shared.message = Message(description: "Menu Command Error", body: (result.stderr + result.stdout).joined(separator: "\n"))
                    }
                }
            } catch {
                MessageModel.shared.message = Message(description: "Menu Command Error", body: String(describing: error))
            }
        }
    }

    @objc private func openSettings() {
        WorkspaceControlsPanelController.shared.dismiss()
        ShortcutSettingsModel.shared.requestWindowOpen()
    }
    @objc private func openWorkspaceControls() {
        Task { @MainActor in WorkspaceControlsPanelController.shared.show() }
    }
    @objc private func alwaysFloatApp() { createQuickFloatingRule(match: .application) }
    @objc private func floatThisWindow() { createQuickFloatingRule(match: nil) }

    func createQuickFloatingRule(for focus: LiveFocus, match: QuickFloatingRuleMatch?) {
        guard let window = focus.windowOrNil as? MacWindow,
              let bundleId = window.macApp.rawAppBundleId else { return }
        capturedRuleTarget = QuickFloatingRuleTarget(window: window, focus: focus, bundleId: bundleId,
            pid: window.macApp.pid, launchDate: window.macApp.nsApp.launchDate, workspaceId: focus.workspace.id)
        createQuickFloatingRule(match: match)
    }

    private func createQuickFloatingRule(match requestedMatch: QuickFloatingRuleMatch?) {
        guard let target = capturedRuleTarget else { return }
        Task { @MainActor in
            let title = (try? await target.window.title) ?? ""
            let selectedMatch: QuickFloatingRuleMatch
            if let requestedMatch { selectedMatch = requestedMatch }
            else {
                guard !title.isEmpty else {
                    showQuickRuleMessage("This window has no title", details: "A title rule needs a nonempty window title.")
                    return
                }
                let alert = NSAlert()
                alert.messageText = "Create a floating rule for this window?"
                alert.informativeText = "\(target.window.macApp.name ?? target.bundleId) · \(title)"
                let matchPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
                matchPicker.addItems(withTitles: ["Exact title", "Title starts with"])
                alert.accessoryView = matchPicker
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Create Rule")
                guard alert.runModal() == .alertSecondButtonReturn else { return }
                selectedMatch = matchPicker.indexOfSelectedItem == 1 ? .titlePrefix(title) : .exactTitle(title)
            }

            let configText: String
            do { configText = try ConfigFileStore.read(preferredEditableConfigUrl()) ?? "" }
            catch { showQuickRuleMessage("Could not read window rules", details: error.localizedDescription); return }
            if let conflict = QuickFloatingRuleDocument.conflict(in: configText, bundleId: target.bundleId,
                                                                  appName: target.window.macApp.name, title: title) {
                let details = conflict.actions.isEmpty ? "The earlier matching rule has no readable actions." : conflict.actions.joined(separator: " → ")
                let alert = NSAlert()
                alert.messageText = "An earlier window rule may match"
                alert.informativeText = "Rule \(conflict.ruleIndex + 1) runs first and stops further callbacks. Existing actions: \(details)"
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Open Configuration")
                if alert.runModal() == .alertSecondButtonReturn { openConfig() }
                return
            }

            let matchingWindows = MacWindow.allWindows.filter { $0.macApp.rawAppBundleId == target.bundleId }
            var matchingTitles: [String] = []
            for window in matchingWindows {
                let currentTitle = (try? await window.title) ?? ""
                guard !currentTitle.isEmpty else { continue }
                if QuickFloatingRuleDocument.matchesTitle(currentTitle, with: selectedMatch) { matchingTitles.append(currentTitle) }
            }
            let matchDescription: String
            switch selectedMatch {
                case .application: matchDescription = "all windows from this app"
                case .exactTitle(let value): matchDescription = "the exact title ‘\(value)’"
                case .titlePrefix(let value): matchDescription = "titles starting with ‘\(value)’"
            }
            let review = NSAlert()
            review.messageText = "Save floating rule?"
            review.informativeText = "App: \(target.window.macApp.name ?? target.bundleId) (\(target.bundleId))\nRule: \(matchDescription)\nCurrently matching windows: \(matchingTitles.isEmpty ? "none" : matchingTitles.joined(separator: ", "))"
            review.addButton(withTitle: "Cancel")
            review.addButton(withTitle: "Save Rule")
            guard review.runModal() == .alertSecondButtonReturn else { return }

            let rule = QuickFloatingRuleDocument.rule(bundleId: target.bundleId, match: selectedMatch)
            persistSettingsDocumentEdit(model: ShortcutSettingsModel.shared, settingIDs: ["on-window-detected"], onSaved: {
                guard target.isStillCurrent else {
                    self.showQuickRuleMessage("Rule saved", details: "The captured window changed before it could be floated. The rule will apply to future matching windows.")
                    return
                }
                guard case .cmd(let command) = parseCommand("layout floating") else { return }
                let environment = CmdEnv.defaultEnv.withFocus(target.focus)
                Task {
                    do {
                        try await runLightSession(.menuBarButton, .forceRun, shouldSchedulePostRefresh: true) {
                            _ = try await [command].runCmdSeq(environment, .emptyStdin)
                        }
                    } catch { self.showQuickRuleMessage("Rule saved, but the window could not be floated", details: error.localizedDescription) }
                }
            }, onFailure: { error in
                self.showQuickRuleMessage("Could not save floating rule", details: error.localizedDescription)
            }) { current in
                guard QuickFloatingRuleDocument.conflict(in: current, bundleId: target.bundleId,
                                                         appName: target.window.macApp.name, title: title) == nil else {
                    throw SettingsDisplayError("An earlier stopping window rule now matches. Review the rules before saving.")
                }
                return try QuickFloatingRuleDocument.adding(rule, to: current)
            }
        }
    }

    private func showQuickRuleMessage(_ title: String, details: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = details
        alert.runModal()
    }
    @objc private func copyVersion() { "\(winMuxAppName) v\(winMuxAppVersion) \(gitHash)".copyToClipboard() }
    @objc private func openConfig() {
        WorkspaceControlsPanelController.shared.dismiss()
        NSWorkspace.shared.open(findCustomConfigUrl().urlOrNil ?? ((try? ensureBootstrapConfigExistsIfNeeded()) ?? preferredEditableConfigUrl()))
    }
    @objc private func openDiagnostics() { DiagnosticsWindowController.shared.show() }
    @objc private func refreshNativeSpaces() { runtime.workspaceBackend.observation?.requestRead() }
    @objc private func resetMinimumSizes() {
        let alert = NSAlert()
        alert.messageText = "Reset learned minimum window sizes?"
        alert.informativeText = "This clears saved per-app minimum sizes and current observations. Window positions and your configuration are unchanged."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        PersistedAppMinimums.shared.reset()
    }
    @objc private func recoverWindows() {
        let alert = NSAlert()
        alert.messageText = "Recover windows from a previous session?"
        alert.informativeText = "WinMux will pause tiling and restore their original positions and sizes. Windows whose app identity changed or whose original display is disconnected will be skipped."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Pause Tiling and Recover")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Task {
            let report = await WindowRecoveryController.shared.recoverAfterCrash()
            MessageModel.shared.message = Message(description: "Window Recovery", body: report)
        }
    }
    @objc private func checkUpdates() { checkForUpdates?() }
    @objc private func openRepository() { NSWorkspace.shared.open(URL(string: forkRepositoryURL)!) }
    @objc private func openIssue() { NSWorkspace.shared.open(URL(string: forkRepositoryURL + "/issues/new")!) }
    @objc private func quit() { terminateApp() }

}

@MainActor
private struct QuickFloatingRuleTarget {
    let window: MacWindow
    let focus: LiveFocus
    let bundleId: String
    let pid: Int32
    let launchDate: Date?
    let workspaceId: WorkspaceId

    var isStillCurrent: Bool {
        var node: TreeNode? = window
        var currentWorkspace: Workspace?
        while let current = node {
            if let workspace = current as? Workspace { currentWorkspace = workspace; break }
            node = current.parent
        }
        guard MacWindow.allWindowsMap[window.windowId] === window,
              window.macApp.pid == pid, window.macApp.nsApp.launchDate == launchDate,
              window.macApp.rawAppBundleId == bundleId, currentWorkspace?.id == workspaceId,
              !window.macApp.nsApp.isTerminated else { return false }
        return true
    }
}

final class MenuCommandPayload {
    let commands: [any Command]
    init(commands: [any Command]) { self.commands = commands }
}

func menuCommandRequiresWindow(_ command: any Command) -> Bool {
    switch command {
        case is FocusCommand, is MoveCommand, is JoinWithCommand, is StackWithCommand,
             is SwapCommand, is ResizeCommand, is LayoutCommand, is WorkspaceLayoutCommand, is FullscreenCommand,
             is MoveNodeToWorkspaceCommand, is MoveNodeToMonitorCommand, is MoveNodeToProjectCommand,
             is SplitCommand, is CloseCommand, is CloseAllWindowsButCurrentCommand,
             is MacosNativeMinimizeCommand, is MacosNativeFullscreenCommand: true
        default: false
    }
}

@MainActor
func menuWorkspaceTargets() -> [(workspace: Workspace, target: String)] {
    userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: focus.workspace)
        .filter { $0.projectId == focus.workspace.projectId }
        .map { workspace in
            let target = workspace.usesAutomaticDisplayName
                ? automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: focus.workspace).map(String.init) ?? workspace.name
                : workspace.name
            return (workspace, target)
        }
}
