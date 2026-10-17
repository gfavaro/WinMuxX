import AppKit
import Common

enum EffectiveLeaf {
    case window(Window)
    case emptyWorkspace(Workspace)
}
extension LiveFocus {
    var asLeaf: EffectiveLeaf {
        if let windowOrNil { .window(windowOrNil) } else { .emptyWorkspace(workspace) }
    }
}

/// This object should be only passed around but never memorized
/// Alternative name: ResolvedFocus
struct LiveFocus: WinMuxAny, Equatable {
    let windowOrNil: Window?
    var workspace: Workspace

    @MainActor fileprivate var frozen: FrozenFocus {
        return FrozenFocus(
            windowId: windowOrNil?.windowId,
            workspaceName: workspace.name,
            monitorId_oneBased: workspace.workspaceMonitor.monitorId_oneBased ?? 0,
        )
    }
}

/// "old", "captured", "frozen in time" Focus
/// It's safe to keep a hard reference to this object.
/// Unlike in LiveFocus, information inside FrozenFocus isn't guaranteed to be self-consistent.
/// window - workspace - monitor relation could change since the moment object was created
struct FrozenFocus: WinMuxAny, Equatable, Sendable {
    let windowId: UInt32?
    let workspaceName: String
    // monitorId is not part of the focus. We keep it here only for 'on-focused-monitor-changed' to work
    let monitorId_oneBased: Int

    @MainActor var liveOrNil: LiveFocus? { // Important: don't access focus.monitorId here. monitorId is not part of the focus. Always prefer workspace
        let window: Window? = windowId.flatMap { Window.get(byId: $0) }
        guard let workspace = Workspace.existing(byName: workspaceName) else { return nil }

        let workspaceFocus = workspace.toLiveFocus()
        let windowFocus = window?.takeIf(\.participatesInWorkspaceFocus)?.toLiveFocusOrNil() ?? workspaceFocus

        return workspaceFocus.workspace != windowFocus.workspace
            ? workspaceFocus // If window and workspace become separated prefer workspace
            : windowFocus
    }

    @MainActor var live: LiveFocus { liveOrNil ?? mainMonitor.activeWorkspace.toLiveFocus() }

    func replacingWorkspaceName(_ oldName: String, with newName: String) -> FrozenFocus {
        workspaceName == oldName
            ? FrozenFocus(windowId: windowId, workspaceName: newName, monitorId_oneBased: monitorId_oneBased)
            : self
    }
}

struct RefreshSessionFocusSnapshot: Sendable {
    let focus: FrozenFocus
    let prevFocus: FrozenFocus?
    let prevPrevFocus: FrozenFocus?
    let fallbackWhenFocusedWindowCloses: FrozenFocus?
}

@TaskLocal
var _refreshSessionFocusSnapshot: RefreshSessionFocusSnapshot? = nil
var refreshSessionFocusSnapshot: RefreshSessionFocusSnapshot? { _refreshSessionFocusSnapshot }

@MainActor
func captureRefreshSessionFocusSnapshot() -> RefreshSessionFocusSnapshot {
    let currentFocus = focus
    return RefreshSessionFocusSnapshot(
        focus: runtime.focus.requested,
        prevFocus: runtime.focus.previous,
        prevPrevFocus: runtime.focus.previousPrevious,
        fallbackWhenFocusedWindowCloses: currentFocus.windowOrNil.map { currentFocus.workspace.toLiveFocus(excluding: $0).frozen },
    )
}

func debugDescribe(_ focus: LiveFocus?) -> String {
    guard let focus else { return "nil" }
    return "w:\(focus.windowOrNil?.windowId.description ?? "nil") ws:\(focus.workspace.name)"
}

func debugDescribe(_ focus: FrozenFocus?) -> String {
    guard let focus else { return "nil" }
    return "w:\(focus.windowId?.description ?? "nil") ws:\(focus.workspaceName)"
}

@MainActor
func debugDescribe(_ snapshot: RefreshSessionFocusSnapshot?) -> String {
    guard let snapshot else { return "nil" }
    return "focus[\(debugDescribe(snapshot.focus.liveOrNil))] prev[\(debugDescribe(snapshot.prevFocus?.liveOrNil))] prevPrev[\(debugDescribe(snapshot.prevPrevFocus?.liveOrNil))] closeFallback[\(debugDescribe(snapshot.fallbackWhenFocusedWindowCloses?.liveOrNil))]"
}

@MainActor
final class WorkspaceFocusState {
    lazy var requested: FrozenFocus = {
        let monitor = mainMonitor
        return FrozenFocus(windowId: nil, workspaceName: monitor.activeWorkspace.name,
                           monitorId_oneBased: monitor.monitorId_oneBased ?? 0)
    }()
    lazy var lastKnown: FrozenFocus = requested
    var previous: FrozenFocus?
    var previousPrevious: FrozenFocus?
    var previousWorkspaceName: String? {
        didSet { previousWorkspaceDate = .now }
    }
    var previousWorkspaceDate: Date = .distantPast
    var runningCallbacks = false
}

@MainActor
func replaceWorkspaceNameInFocusState(oldName: String, newName: String) {
    runtime.focus.requested = runtime.focus.requested.replacingWorkspaceName(oldName, with: newName)
    runtime.focus.lastKnown = runtime.focus.lastKnown.replacingWorkspaceName(oldName, with: newName)
    runtime.focus.previous = runtime.focus.previous?.replacingWorkspaceName(oldName, with: newName)
    runtime.focus.previousPrevious = runtime.focus.previousPrevious?.replacingWorkspaceName(oldName, with: newName)
    if _prevFocusedWorkspaceName == oldName {
        _prevFocusedWorkspaceName = newName
    }
}

/// Global focus.
/// Commands must be cautious about accessing this property directly. There are legitimate cases.
/// But, in general, commands must firstly check --window-id, --workspace, WINMUX_WINDOW_ID env and
/// WINMUX_WORKSPACE env before accessing the global focus.
@MainActor var focus: LiveFocus { runtime.focus.requested.live }

/// Unlike derived live focus, this changes only when focus is explicitly assigned.
@MainActor func captureRequestedFocus() -> FrozenFocus { runtime.focus.requested }

@MainActor func setFocus(to newFocus: LiveFocus) -> Bool {
    if runtime.focus.requested == newFocus.frozen {
        return newFocus.workspace.isVisible || newFocus.workspace.workspaceMonitor.setActiveWorkspace(newFocus.workspace)
    }
    let oldFocus = focus
    let status = newFocus.workspace.workspaceMonitor.setActiveWorkspace(newFocus.workspace)
    guard status else { return false }

    // Normalize mruWindow when focus away from a workspace
    if oldFocus.workspace != newFocus.workspace {
        oldFocus.windowOrNil?.markAsMostRecentChild()
    }

    runtime.focus.requested = newFocus.frozen
    newFocus.windowOrNil?.markAsMostRecentChild()
    return true
}
extension Window {
    @MainActor func focusWindow() -> Bool {
        if let focus = toLiveFocusOrNil() {
            return setFocus(to: focus)
        } else {
            // todo We should also exit-native-hidden/unminimize[/exit-native-fullscreen?] window if we want to fix ID-B6E178F2
            //      and retry to focus the window. Otherwise, it's not possible to focus minimized/hidden windows
            return false
        }
    }

    @MainActor func toLiveFocusOrNil() -> LiveFocus? { visualWorkspace.map { LiveFocus(windowOrNil: self, workspace: $0) } }
}
extension Workspace {
    @MainActor func focusWorkspace() -> Bool {
        if self != focus.workspace {
            WorkspaceSidebarPanel.suppressEdgeTrapForWorkspaceActivation()
        }
        return setFocus(to: toLiveFocus())
    }

    func toLiveFocus() -> LiveFocus {
        toLiveFocus(excluding: nil)
    }

    func toLiveFocus(excluding excludedWindow: Window?) -> LiveFocus {
        if let wd = mostRecentWorkspaceFocusableWindowRecursive(excluding: excludedWindow) {
            LiveFocus(windowOrNil: wd, workspace: self)
        } else {
            LiveFocus(windowOrNil: nil, workspace: self) // emptyWorkspace
        }
    }
}

// Used by workspace-back-and-forth and focus-back-and-forth.
@MainActor var _prevFocusedWorkspaceName: String? {
    get { runtime.focus.previousWorkspaceName }
    set { runtime.focus.previousWorkspaceName = newValue }
}
@MainActor var prevFocusedWorkspaceDate: Date {
    get { runtime.focus.previousWorkspaceDate }
    set { runtime.focus.previousWorkspaceDate = newValue }
}
@MainActor var prevFocusedWorkspace: Workspace? { _prevFocusedWorkspaceName.flatMap(Workspace.existing(byName:)) }

@MainActor var prevFocus: LiveFocus? {
    guard let previous = runtime.focus.previous?.liveOrNil, previous != focus else { return nil }
    return previous
}
@MainActor var prevPrevFocus: LiveFocus? {
    guard let previous = runtime.focus.previousPrevious?.liveOrNil, previous != focus else { return nil }
    return previous
}

// Should be called in refreshSession
@MainActor func checkOnFocusChangedCallbacks() {
    if refreshSessionEvent?.isStartup == true {
        return
    }
    let focus = focus
    let frozenFocus = focus.frozen
    let lastKnownFocusBefore = runtime.focus.lastKnown
    let prevFocusBefore = runtime.focus.previous
    let prevPrevFocusBefore = runtime.focus.previousPrevious
    var hasFocusChanged = false
    var hasFocusedWorkspaceChanged = false
    var hasFocusedMonitorChanged = false
    if frozenFocus != runtime.focus.lastKnown {
        runtime.focus.previousPrevious = runtime.focus.previous
        runtime.focus.previous = runtime.focus.lastKnown
        hasFocusChanged = true
    }
    if frozenFocus.workspaceName != runtime.focus.lastKnown.workspaceName {
        _prevFocusedWorkspaceName = runtime.focus.lastKnown.workspaceName
        hasFocusedWorkspaceChanged = true
    }
    if frozenFocus.monitorId_oneBased != runtime.focus.lastKnown.monitorId_oneBased {
        hasFocusedMonitorChanged = true
    }
    runtime.focus.lastKnown = frozenFocus

    if runtime.focus.runningCallbacks { return }
    runtime.focus.runningCallbacks = true
    defer { runtime.focus.runningCallbacks = false }
    if hasFocusChanged {
        onFocusChanged(focus)
    }
    if let _prevFocusedWorkspaceName, hasFocusedWorkspaceChanged {
        onWorkspaceChanged(_prevFocusedWorkspaceName, frozenFocus.workspaceName)
    }
    if hasFocusedMonitorChanged {
        onFocusedMonitorChanged(focus)
    }
    if hasFocusChanged {
        debugFocusLog(
            "checkOnFocusChangedCallbacks event=\(refreshSessionEvent.prettyDescription) lastKnown=\(debugDescribe(lastKnownFocusBefore.liveOrNil)) -> focus=\(debugDescribe(focus)) prev=\(debugDescribe(prevFocusBefore?.liveOrNil)) -> \(debugDescribe(runtime.focus.previous?.liveOrNil)) prevPrev=\(debugDescribe(prevPrevFocusBefore?.liveOrNil)) -> \(debugDescribe(runtime.focus.previousPrevious?.liveOrNil))"
        )
    }
}

@MainActor private func onFocusedMonitorChanged(_ focus: LiveFocus) {
    broadcastEvent(.focusedMonitorChanged(
        workspace: focus.workspace.name,
        monitorId_oneBased: focus.workspace.workspaceMonitor.monitorId_oneBased ?? 0,
    ))
    if config.onFocusedMonitorChanged.isEmpty { return }
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    // todo potential optimization: don't run runSession if we are already in runSession
    let owner = runtime
    Task {
        try await owner.withValue {
            try await runLightSession(.onFocusedMonitorChanged, token) {
                _ = try await config.onFocusedMonitorChanged.runCmdSeq(.defaultEnv.withFocus(focus), .emptyStdin)
            }
        }
    }
}
@MainActor private func onFocusChanged(_ focus: LiveFocus) {
    broadcastEvent(.focusChanged(
        windowId: focus.windowOrNil?.windowId,
        workspace: focus.workspace.name,
    ))
    if config.onFocusChanged.isEmpty { return }
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    // todo potential optimization: don't run runSession if we are already in runSession
    let owner = runtime
    Task {
        try await owner.withValue {
            try await runLightSession(.onFocusChanged, token) {
                _ = try await config.onFocusChanged.runCmdSeq(.defaultEnv.withFocus(focus), .emptyStdin)
            }
        }
    }
}

@MainActor private func onWorkspaceChanged(_ oldWorkspace: String, _ newWorkspace: String) {
    broadcastEvent(.workspaceChanged(
        workspace: newWorkspace,
        prevWorkspace: oldWorkspace,
    ))
    if let exec = config.execOnWorkspaceChange.first {
        let process = Process()
        process.executableURL = URL(filePath: exec)
        process.arguments = Array(config.execOnWorkspaceChange.dropFirst())
        var environment = config.execConfig.envVariables
        environment[WINMUX_FOCUSED_WORKSPACE] = newWorkspace
        environment[WINMUX_PREV_WORKSPACE] = oldWorkspace
        environment[WINMUX_WORKSPACE] = newWorkspace
        process.environment = environment
        _ = Result { try process.run() }
    }
}
