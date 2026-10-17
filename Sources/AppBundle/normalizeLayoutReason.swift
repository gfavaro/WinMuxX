@MainActor
func normalizeLayoutReason() async throws {
    for workspace in Workspace.all {
        try checkCancellation()
        let windows: [Window] = workspace.allLeafWindowsRecursive
        try await _normalizeLayoutReason(workspace: workspace, windows: windows)
    }
    try await _normalizeLayoutReason(workspace: focus.workspace, windows: macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self))
    try await validateStillPopups()
}

@MainActor
private func validateStillPopups() async throws {
    for node in macosPopupWindowsContainer.children {
        guard let popup = node as? MacWindow else { continue }
        let windowLevel = getWindowLevel(for: popup.windowId)
        if try await popup.isWindowHeuristic(windowLevel), popup.parent is MacosPopupWindowsContainer {
            try await WindowDetectionOperations.shared.run(popup) {
                guard popup.parent is MacosPopupWindowsContainer else { return }
                try await popup.relayoutWindow(on: focus.workspace)
                WindowDetectionOperations.shared.resolvedPopup(popup)
                try await tryOnWindowDetected(popup)
            }
        }
    }
}

@MainActor
private func _normalizeLayoutReason(workspace: Workspace, windows: [Window]) async throws {
    typealias Observation = (token: UInt64, full: Bool, mini: Bool)
    var states = [Observation?](repeating: nil, count: windows.count)
    try await withThrowingTaskGroup(of: (Int, Observation?).self) { group in
        for (index, window) in windows.enumerated() {
            if let full = window.lastKnownNativeFullscreen, let mini = window.lastKnownNativeMinimized {
                states[index] = (window.nativeStateObservationToken(), full, mini)
            } else {
                group.addTask { @Sendable @MainActor in
                    let token = window.nativeStateObservationToken()
                    guard let state = try await window.readNativeState(), token == window.nativeStateObservationToken() else { return (index, nil) }
                    window.recordObservedNativeState(fullscreen: state.fullscreen, minimized: state.minimized, token: token)
                    return (index, (token, state.fullscreen, state.minimized))
                }
            }
        }
        for try await (index, observation) in group { states[index] = observation }
    }
    for (index, window) in windows.enumerated() {
        try checkCancellation()
        guard window.parent != nil,
              window.nodeWorkspace === workspace || window.parent is MacosMinimizedWindowsContainer else { continue }
        var observation = states[index]
        var hidden = !config.automaticallyUnhideMacosHiddenApps && (window.app as? MacApp)?.nsApp.isHidden == true
        let willMutate = observation.map { value in
            let unconventional = value.full || value.mini || hidden
            if case .standard = window.layoutReason { return unconventional }
            return !unconventional
        } ?? false
        if willMutate || observation?.token != window.nativeStateObservationToken() {
            let token = window.nativeStateObservationToken()
            let parent = window.parent
            guard let fresh = try await window.readNativeState(), token == window.nativeStateObservationToken(),
                  window.parent === parent else { continue }
            try checkCancellation()
            hidden = !config.automaticallyUnhideMacosHiddenApps && (window.app as? MacApp)?.nsApp.isHidden == true
            observation = (token, fresh.fullscreen, fresh.minimized)
            window.recordObservedNativeState(fullscreen: fresh.fullscreen, minimized: fresh.minimized, token: token)
        }
        guard let observation else { continue }
        let isMacosFullscreen = observation.full, isMacosMinimized = observation.mini
        let isMacosWindowOfHiddenApp = !isMacosFullscreen && !isMacosMinimized && hidden
        let mru = window.nodeWorkspace?.mostRecentWindowRecursive
        let requestedFocus = captureRequestedFocus()
        defer {
            if captureRequestedFocus() == requestedFocus, let mru, mru !== window, mru.parent != nil {
                mru.markAsMostRecentChild()
            }
        }
        switch window.layoutReason {
            case .standard:
                guard window.parent != nil else { continue }
                switch true {
                    case isMacosFullscreen:
                        window.rememberMacOsLayoutOrigin()
                        window.bind(to: workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                    case isMacosMinimized:
                        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
                        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
                    case isMacosWindowOfHiddenApp:
                        window.rememberMacOsLayoutOrigin()
                        window.bind(to: workspace.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                    default: break
                }
            case .macos(let prevParentKind, let prevWorkspaceName):
                if !isMacosFullscreen && !isMacosMinimized && !isMacosWindowOfHiddenApp {
                    try await exitMacOsNativeUnconventionalState(
                        window: window,
                        prevParentKind: prevParentKind,
                        prevWorkspaceName: prevWorkspaceName,
                        workspace: workspace,
                    )
                }
        }
    }
}

@MainActor
func exitMacOsNativeUnconventionalState(
    window: Window,
    prevParentKind: NonLeafTreeNodeKind,
    prevWorkspaceName: String?,
    workspace fallbackWorkspace: Workspace,
) async throws {
    window.layoutReason = .standard
    let workspace = prevWorkspaceName
        .flatMap { Workspace.existing(byName: $0) }
        ?? fallbackWorkspace
    workspace.seedMonitorIfNeeded(fallbackWorkspace.workspaceMonitor)
    switch prevParentKind {
        case .workspace:
            window.bindAsFloatingWindow(to: workspace)
        case .tilingContainer:
            try await window.relayoutWindow(on: workspace, forceTile: true)
        case .macosPopupWindowsContainer: // Since the window was minimized/fullscreened it was mistakenly detected as popup. Relayout the window
            try await window.relayoutWindow(on: workspace)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer: // wtf case, should never be possible. But If encounter it, let's just re-layout window
            try await window.relayoutWindow(on: workspace)
    }
}
