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
        _ = try await callback.run.runCmdSeq(.defaultEnv.copy(\.windowId, window.windowId), .emptyStdin)
        if !callback.checkFurtherCallbacks {
            return
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
        if let regex = matcher.appNameRegexSubstring, !(window.app.name ?? "").contains(regex) {
            return false
        }
        if let workspace = matcher.workspace, workspace != window.nodeWorkspace?.name {
            return false
        }
        return true
    }
}
