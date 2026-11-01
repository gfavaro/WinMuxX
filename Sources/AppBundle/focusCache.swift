import Common
import Foundation


@MainActor struct WorkspaceProjectFocusHold {
    let projectId: WorkspaceProjectId
    let expiresAt: Date
}


@MainActor struct WindowClosureFocusHold {
    let workspaceId: WorkspaceId
    let appPid: Int32
    let expiresAt: Date
}

@MainActor
final class NativeFocusState {
    var lastKnownWindowID: UInt32?
    var projectHold: WorkspaceProjectFocusHold?
    var windowClosureHold: WindowClosureFocusHold?
}

@MainActor
func holdFocusAfterLastWindowClosure(on workspace: Workspace, appPid: Int32, now: Date = .now) {
    runtime.nativeFocus.windowClosureHold = WindowClosureFocusHold(workspaceId: workspace.id, appPid: appPid, expiresAt: now.addingTimeInterval(0.25))
}

@MainActor
private func shouldIgnoreNativeFocusAfterWindowClosure(_ nativeFocused: Window?, now: Date) -> Bool {
    guard let hold = runtime.nativeFocus.windowClosureHold else { return false }
    guard now < hold.expiresAt, focus.workspace.id == hold.workspaceId else {
        runtime.nativeFocus.windowClosureHold = nil
        return false
    }
    guard let nativeFocused, let workspace = nativeFocused.visualWorkspace else { return false }
    // Closing the final document can make macOS promote another document of
    // the same app, even when it is parked in an inactive workspace.
    return nativeFocused.app.pid == hold.appPid && workspace.id != hold.workspaceId && !workspace.isVisible
}

@MainActor
func holdFocusOnWorkspaceProject(_ projectId: WorkspaceProjectId, for duration: TimeInterval) {
    runtime.nativeFocus.projectHold = WorkspaceProjectFocusHold(
        projectId: projectId,
        expiresAt: Date().addingTimeInterval(duration),
    )
}

@MainActor
func clearFocusOnWorkspaceProjectHold(_ projectId: WorkspaceProjectId? = nil) {
    guard projectId == nil || runtime.nativeFocus.projectHold?.projectId == projectId else { return }
    runtime.nativeFocus.projectHold = nil
}

@MainActor
private func activeWorkspaceProjectFocusHold(now: Date = .now) -> WorkspaceProjectFocusHold? {
    guard let hold = runtime.nativeFocus.projectHold else { return nil }
    if hold.expiresAt <= now {
        runtime.nativeFocus.projectHold = nil
        return nil
    }
    return hold
}

@MainActor
private func shouldIgnoreNativeFocusDuringProjectHold(_ nativeFocused: Window?) -> Bool {
    guard let hold = activeWorkspaceProjectFocusHold(),
          let nativeFocused
    else {
        return false
    }
    return nativeFocused.visualWorkspace?.projectId != hold.projectId
}

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to runtime.nativeFocus.lastKnownWindowID)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?, now: Date = .now) {
    // AX can report a key-window change caused by stacking while a viewport
    // gesture is in flight. A real click ends the gesture in GlobalObserver.
    guard !WorkspaceScrollingGestureController.shared.isMotionActive else { return }
    if ignoresCrossWorkspaceActivation(nativeFocused) { return }
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    let lastKnownNativeFocusedWindowIdBefore = runtime.nativeFocus.lastKnownWindowID
    if shouldIgnoreNativeFocusAfterWindowClosure(nativeFocused, now: now) {
        runtime.nativeFocus.lastKnownWindowID = nil
        debugFocusLog("updateFocusCache ignoredWindowClosure nativeFocused=\(nativeFocused?.windowId.description ?? "nil") logicalFocus=\(debugDescribe(focus))")
        return
    }
    if shouldIgnoreNativeFocusDuringProjectHold(nativeFocused) {
        runtime.nativeFocus.lastKnownWindowID = nil
        debugFocusLog(
            "updateFocusCache ignoredProjectHold event=\(refreshSessionEvent.prettyDescription) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") lastKnownNative=\(lastKnownNativeFocusedWindowIdBefore?.description ?? "nil") heldProject=\(activeWorkspaceProjectFocusHold()?.projectId.rawValue ?? "nil") logicalFocus=\(debugDescribe(focus))"
        )
        return
    }
    if nativeFocusHoldRejects(nativeFocused) {
        runtime.nativeFocus.lastKnownWindowID = nil
        debugFocusLog("updateFocusCache ignoredNativeFocusHold nativeFocused=\(nativeFocused?.windowId.description ?? "nil")")
        return
    }
    if nativeFocused?.windowId != runtime.nativeFocus.lastKnownWindowID {
        if let nativeFocused, shouldBringActivatedWindowHere(nativeFocused, activation: runtime.refresh.pendingActivation) {
            nativeFocused.bind(to: focus.workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
        if let nativeFocused, let live = nativeFocused.toLiveFocusOrNil() {
            _ = setFocus(to: live, origin: .native)
        }
        runtime.nativeFocus.lastKnownWindowID = nativeFocused?.windowId
    }
    (nativeFocused?.app as? MacApp)?.lastNativeFocusedWindowId = nativeFocused?.windowId
    debugFocusLog(
        "updateFocusCache event=\(refreshSessionEvent.prettyDescription) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") lastKnownNative=\(lastKnownNativeFocusedWindowIdBefore?.description ?? "nil") -> \(runtime.nativeFocus.lastKnownWindowID?.description ?? "nil") logicalFocus=\(debugDescribe(focus))"
    )
}

/// A floating window the user activates while on another workspace comes to that workspace
/// instead of taking the user to its own: floating windows (Settings, chat, a calculator) are in
/// no layout, so moving one rearranges nothing. Only for an activation of this app made from the
/// current workspace, so a focus report that lags a workspace switch moves nothing; and only from
/// a hidden workspace. A window another display shows is focused there; tiled windows and excluded
/// apps keep following the activation; native Spaces handles its own windows.
@MainActor
func shouldBringActivatedWindowHere(_ window: Window, activation: RefreshActivationContext?) -> Bool {
    guard runtime.workspaceBackend.capabilities.parksInactiveWindows,
          let activation, activation.pid == window.app.pid, activation.workspaceName == focus.workspace.name,
          window.isFloating, let source = window.nodeWorkspace, source !== focus.workspace, !source.isVisible
    else { return false }
    return config.followAppActivation.follows(window.app.rawAppBundleId)
}

@MainActor
func ignoresCrossWorkspaceActivation(_ window: Window?) -> Bool {
    guard let window, let workspace = window.nodeWorkspace, workspace !== focus.workspace else { return false }
    return !config.followAppActivation.follows(window.app.rawAppBundleId)
}
