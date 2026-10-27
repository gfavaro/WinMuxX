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

@MainActor
private func onWindowDetected(_ window: Window) async throws {
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
        _ = try await callback.run.runCmdSeq(context, .emptyStdin)
        if !callback.checkFurtherCallbacks {
            return
        }
    }
}

/// Rule commands native mode skipped, for doctor. Native windows register during
/// reconciliation, before native commands can run, so rules apply only what native
/// tiling implements for a new window: floating or tiling it.
@MainActor var nativeSkippedWindowRuleCommands: Set<String> = []

@MainActor
func applyNativeWindowDetectedRules(_ window: Window, stillOwned: () -> Bool) async throws {
    for callback in config.onWindowDetected where try await callback.matches(window) {
        guard stillOwned() else { return }
        for command in callback.run {
            if let move = command as? MoveNodeToWorkspaceCommand, runtime.workspaceBackend.accepts(move) {
                // Existing windows stay put at startup; only windows opened later are moved.
                if runtime.workspaceBackend.nativeTiling.hasCompletedInitialLayout { scheduleNativeRuleMove(move, window: window.windowId) }
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
        for _ in 0..<40 where !owner.workspaceBackend.nativeTiling.ready { try? await Task.sleep(for: .milliseconds(50)) }
        let io = CmdIo(stdin: .emptyStdin)
        if !(await owner.workspaceBackend.nativeWindowMoves.run(move.args, env: .defaultEnv.copy(\.windowId, id), io: io)) {
            nativeSkippedWindowRuleCommands.insert("\(move.args) (failed: \(io.stderr.last ?? "unknown"))")
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
