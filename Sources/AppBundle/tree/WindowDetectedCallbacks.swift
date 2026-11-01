import Common

@MainActor
func tryOnWindowDetected(_ window: Window) async throws {
    guard let parent = window.parent else { return }
    switch parent.cases {
        case .tilingContainer, .workspace:
            // Consume before any suspension so another detected window cannot take it.
            let layout = layoutForNextDetectedWindow
            layoutForNextDetectedWindow = nil
            if let layout { try await applyDetectedWindowLayout(layout, to: window) }
            try await onWindowDetected(window)
            // Rules may move the window to another workspace or change its layout.
            if let layout { try await applyDetectedWindowLayout(layout, to: window) }
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
            try await onWindowDetected(window)
        case .macosPopupWindowsContainer:
            break
    }
}

@MainActor
private func applyDetectedWindowLayout(_ layout: LayoutCmdArgs.LayoutDescription, to window: Window) async throws {
    guard let parent = window.parent else { return }
    switch parent.cases {
        case .tilingContainer, .workspace:
            _ = try await LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [layout]))
                .run(.defaultEnv.copy(\.windowId, window.windowId), .emptyStdin)
        case .macosPopupWindowsContainer, .macosMinimizedWindowsContainer,
             .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer: break
    }
}

/// Commands that send a window to another workspace, display or project.
@MainActor
func isWindowRelocation(_ command: any Command) -> Bool {
    command is MoveNodeToWorkspaceCommand || command is MoveNodeToMonitorCommand || command is MoveNodeToProjectCommand
}

/// A rule's commands for this window. An app-wide routing rule is for the app's ordinary
/// windows: sending its dialog (a save panel, a print or format sheet) to another
/// workspace left the app stuck behind a modal no one could see (WinMux issue #23).
/// Floating and tiling still apply to dialogs.
@MainActor
func windowRuleCommands(_ commands: [any Command], isDialog: Bool) -> [any Command] {
    isDialog ? commands.filter { !isWindowRelocation($0) } : commands
}

/// Asked only when a matching rule would relocate the window, and at most once.
@MainActor
private final class WindowRuleDialogCheck {
    private let window: Window
    private var answer: Bool?
    init(_ window: Window) { self.window = window }
    func isDialog(for commands: [any Command]) async -> Bool {
        guard commands.contains(where: isWindowRelocation) else { return false }
        if let answer { return answer }
        let result = (try? await (window as? MacWindow)?.isDialogHeuristic(getWindowLevel(for: window.windowId))) ?? false
        answer = result
        return result
    }
}

@MainActor
private func onWindowDetected(_ window: Window) async throws {
    let dialog = WindowRuleDialogCheck(window)
    broadcastEvent(.windowDetected(
        windowId: window.windowId,
        workspace: window.nodeWorkspace?.name,
        appBundleId: window.app.rawAppBundleId,
        appName: window.app.name,
    ))
    for callback in config.onWindowDetected where try await callback.matches(window) {
        var context = hookEnvironment(event: "window-detected").copy(\.windowId, window.windowId)
        context.extraEnvironment["WINMUX_WORKSPACE"] = window.nodeWorkspace?.name ?? ""
        context.extraEnvironment["WINMUX_MONITOR_UUID"] = window.nodeWorkspace?.workspaceMonitor.displayUUID ?? ""
        let commands = windowRuleCommands(callback.run, isDialog: await dialog.isDialog(for: callback.run))
        _ = try await commands.runCmdSeq(context, .emptyStdin)
        if !callback.checkFurtherCallbacks {
            return
        }
    }
}

/// Rule commands native mode skipped, for doctor. Native windows register during
/// reconciliation, before native commands can run, so rules apply only what native
/// tiling implements for a new window: floating or tiling it.
@MainActor var nativeSkippedWindowRuleCommands: Set<String> = []
/// Schedules a rule's move for a window opened after launch; tests replace it.
@MainActor var nativeRuleMoveScheduler: (MoveNodeToWorkspaceCommand, UInt32) -> Void = { scheduleNativeRuleMove($0, window: $1) }

@MainActor
func applyNativeWindowDetectedRules(_ window: Window, stillOwned: () -> Bool) async throws {
    let dialog = WindowRuleDialogCheck(window)
    for callback in config.onWindowDetected where try await callback.matches(window) {
        guard stillOwned() else { return }
        let commands = windowRuleCommands(callback.run, isDialog: await dialog.isDialog(for: callback.run))
        guard stillOwned() else { return }
        for command in commands {
            if let move = command as? MoveNodeToWorkspaceCommand, runtime.workspaceBackend.accepts(move) {
                // Existing windows stay put, including ones first seen when their desktop is
                // visited later; only windows opened after launch are moved.
                if !runtime.workspaceBackend.native.windowsPresentAtLaunch.contains(window.windowId) {
                    nativeRuleMoveScheduler(move, window.windowId)
                }
                continue
            }
            guard let layout = command as? LayoutCommand, !layout.args.forNextDetectedWindow,
                  let target = layout.args.toggleBetween.val.first(where: { $0 == .floating || $0 == .tiling }) else {
                nativeSkippedWindowRuleCommands.insert("\(command.args)")
                continue
            }
            if target == .floating, let workspace = window.nodeWorkspace { window.bindAsFloatingWindow(to: workspace) }
        }
        if !callback.checkFurtherCallbacks { return }
    }
}

/// Runs after registration finishes, once native tiling is ready to resolve the window.
@MainActor
private func scheduleNativeRuleMove(_ move: MoveNodeToWorkspaceCommand, window id: UInt32) {
    let owner = runtime
    owner.task {
        _ = await owner.workspaceBackend.native.tiling.waitUntilReady(timeout: .seconds(2))
        let io = CmdIo(stdin: .emptyStdin)
        if !(await owner.workspaceBackend.native.windowMoves.transferWindow(move.args, env: .defaultEnv.copy(\.windowId, id), io: io)) {
            // One entry per rule, keeping its latest failure, so the set stays bounded.
            let rule = "\(move.args)"
            nativeSkippedWindowRuleCommands = nativeSkippedWindowRuleCommands.filter { !$0.hasPrefix(rule + " (failed") }
            nativeSkippedWindowRuleCommands.insert("\(rule) (failed: \(io.stderr.last ?? "unknown"))")
        }
    }
}

extension WindowDetectedCallback {
    @MainActor
    func matches(_ window: Window) async throws -> Bool {
        if let startupMatcher = matcher.duringWinMuxStartup, startupMatcher != isStartup {
            return false
        }
        if let regex = matcher.windowTitleRegexSubstring, !(try await window.title).contains(regex) {
            return false
        }
        if let appId = matcher.appId, appId != window.app.rawAppBundleId {
            return false
        }
        if let regex = matcher.appIdRegex, !(window.app.rawAppBundleId ?? "").contains(regex) {
            return false
        }
        if let regex = matcher.appNameRegexSubstring, !(window.app.name ?? "").contains(regex) {
            return false
        }
        if let workspace = matcher.workspace, workspace != window.nodeWorkspace?.name {
            return false
        }
        return true
    }
}
