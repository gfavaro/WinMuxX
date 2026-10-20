import AppKit
import Combine
import Common

@MainActor
public func installNativeMenuBar(checkForUpdates: (() -> Void)? = nil) {
    NativeActionMenu.shared.install(checkForUpdates: checkForUpdates)
}

@MainActor
final class NativeActionMenu: NSObject, NSMenuDelegate {
    static let shared = NativeActionMenu()
    private var statusItem: NSStatusItem?
    private var observation: AnyCancellable?
    private var appearanceObservation: NSKeyValueObservation?
    private var checkForUpdates: (() -> Void)?
    private var bindings = ActionMenuBindings(mode: nil)
    private var lastIconState: (enabled: Bool, appearance: MenuBarIconAppearance, indicator: MenuBarIndicator, text: String, name: String)?

    func install(checkForUpdates: (() -> Void)?) {
        guard statusItem == nil else { return }
        self.checkForUpdates = checkForUpdates
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        if let button = item.button {
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.initial, .new]) { button, _ in
                Task { @MainActor in
                    let match = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                    WorkspaceSidebarPanel.menuBarColorScheme = match == .aqua ? .light : .dark
                    WorkspaceSidebarPanel.refreshWallpaperContrast()
                }
            }
        }
        updateIcon()
        observation = TrayMenuModel.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    private func updateIcon() {
        let model = TrayMenuModel.shared
        let state = (enabled: model.isEnabled, appearance: model.experimentalUISettings.iconAppearance, indicator: model.experimentalUISettings.indicator, text: model.menuBarWorkspaceIndicator, name: model.menuBarWorkspaceName)
        if let previous = lastIconState, previous.enabled == state.enabled, previous.appearance == state.appearance, previous.indicator == state.indicator, previous.text == state.text, previous.name == state.name { return }
        lastIconState = state
        if model.isEnabled && state.indicator == .workspace {
            statusItem?.length = NSStatusItem.variableLength
            statusItem?.button?.image = nil
            statusItem?.button?.title = state.text
            statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
            statusItem?.button?.toolTip = "WinMux · \(state.name) · Focused display"
            statusItem?.button?.setAccessibilityLabel("WinMux, workspace \(state.name), focused display")
            return
        }
        statusItem?.length = NSStatusItem.squareLength
        statusItem?.button?.title = ""
        statusItem?.button?.setAccessibilityLabel(model.isEnabled ? "WinMux" : "WinMux disabled")
        let image: NSImage?
        if model.isEnabled {
            let monochrome = model.experimentalUISettings.iconAppearance != .color
            image = NSImage(named: monochrome ? "MenuBarIconMonochrome" : "MenuBarIcon")?.copy() as? NSImage
            image?.isTemplate = monochrome
        } else {
            image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "WinMuxX disabled")
        }
        image?.size = NSSize(width: 18, height: 18)
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = "WinMuxX"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        bindings = ActionMenuBindings(mode: activeMode.flatMap { config.modes[$0] })
        menu.addItem(NSMenuItem(title: "WinMuxX · Workspace \(workspaceDisplayName(focus.workspace.name))", action: nil, keyEquivalent: ""))
        if activeMode != mainModeId {
            menu.addItem(NSMenuItem(title: "Mode: \(activeMode ?? "none")", action: nil, keyEquivalent: ""))
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
            submenu.addItem(.separator())
            addCommand("Horizontal", script: "layout horizontal", to: submenu)
            addCommand("Vertical", script: "layout vertical", to: submenu)
            submenu.addItem(.separator())
            addCommand("Swap with Master", script: "swap-with-master", to: submenu)
            addCommand("Toggle Floating", script: "layout floating tiling", to: submenu)
        }
        addCommand("Fullscreen", script: "fullscreen", to: menu)
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

    @objc private func openSettings() { ShortcutSettingsModel.shared.requestWindowOpen() }
    @objc private func copyVersion() { "\(winMuxAppName) v\(winMuxAppVersion) \(gitHash)".copyToClipboard() }
    @objc private func openConfig() {
        NSWorkspace.shared.open(findCustomConfigUrl().urlOrNil ?? ((try? ensureBootstrapConfigExistsIfNeeded()) ?? preferredEditableConfigUrl()))
    }
    @objc private func openDiagnostics() { DiagnosticsWindowController.shared.show() }
    @objc private func resetMinimumSizes() {
        let alert = NSAlert()
        alert.messageText = "Reset learned minimum window sizes?"
        alert.informativeText = "This clears saved per-app minimum sizes and current observations. Window positions and your configuration are unchanged."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        PersistedAppMinimums.shared.reset()
        for window in MacWindow.allWindows { window.resetLearnedMinimum() }
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
