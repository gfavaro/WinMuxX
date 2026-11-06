import Common
import Foundation

@MainActor struct WindowClosureFocusHold {
    let workspaceId: WorkspaceId
    let appPid: Int32
    let expiresAt: Date
}

@MainActor
final class NativeFocusState {
    var lastKnownWindowID: UInt32?
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

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to runtime.nativeFocus.lastKnownWindowID)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?, now: Date = .now) {
    // Recorded with `debug-windows --events-start`: which refresh event delivered this focus and what was decided.
    func note(_ decision: @autoclosure () -> String) {
        guard runtime.events.isRecording else { return } // Nothing is formatted unless recording.
        runtime.events.record(.focusObserved, source: .refresh, generation: runtime.refresh.activationGeneration,
            windowID: nativeFocused?.windowId, workspaceID: nativeFocused?.nodeWorkspace?.id,
            reason: "\(decision()) event:\(refreshSessionEvent?.eventCode ?? "none")")
    }
    if ignoresCrossWorkspaceActivation(nativeFocused) { return note("ignored:excludedApp") }
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return note("ignored:popup")
    }
    let lastKnownNativeFocusedWindowIdBefore = runtime.nativeFocus.lastKnownWindowID
    if shouldIgnoreNativeFocusAfterWindowClosure(nativeFocused, now: now) {
        runtime.nativeFocus.lastKnownWindowID = nil
        debugLog(.focus, "updateFocusCache ignoredWindowClosure nativeFocused=\(nativeFocused?.windowId.description ?? "nil") logicalFocus=\(debugDescribe(focus))")
        return note("ignored:windowClosure")
    }
    // The launching app has its window now; focus may be taken back from it again.
    if let pid = nativeFocused?.app.pid, pid == runtime.refresh.windowlessActivationPid {
        runtime.refresh.windowlessActivationPid = nil
    }
    if nativeFocused?.windowId != runtime.nativeFocus.lastKnownWindowID {
        if let nativeFocused {
            if let reason = bringActivatedWindowHereVerdict(nativeFocused, activation: runtime.refresh.pendingActivation) {
                note("focused notMoved:\(reason)")
            } else {
                nativeFocused.bind(to: focus.workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                // As explicit moves do, so lock-screen recovery does not restore it to its old workspace.
                syncClosedWindowsCacheToCurrentWorld()
                note("movedHere")
            }
        } else {
            note("focused:none")
        }
        if let nativeFocused, let live = nativeFocused.toLiveFocusOrNil() {
            _ = setFocus(to: live, origin: .native)
        }
        runtime.nativeFocus.lastKnownWindowID = nativeFocused?.windowId
    } else {
        note("unchanged")
    }
    (nativeFocused?.app as? MacApp)?.lastNativeFocusedWindowId = nativeFocused?.windowId
    debugLog(.focus, "updateFocusCache event=\(refreshSessionEvent.prettyDescription) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") lastKnownNative=\(lastKnownNativeFocusedWindowIdBefore?.description ?? "nil") -> \(runtime.nativeFocus.lastKnownWindowID?.description ?? "nil") logicalFocus=\(debugDescribe(focus))"
    )
}

/// A floating window the user activates while on another workspace comes to that workspace
/// instead of taking the user to its own: floating windows (Settings, chat, a calculator) are in
/// no layout, so moving one rearranges nothing. Only for an activation of this app made from the
/// current workspace, so a focus report that lags a workspace switch moves nothing; and only from
/// a hidden workspace. A window another display shows is focused there; tiled windows and excluded
/// apps keep following the activation.
///
/// Nil when the window comes here, otherwise a fixed code saying why not, for event recording.
@MainActor
func bringActivatedWindowHereVerdict(_ window: Window, activation: RefreshActivationContext?) -> String? {
    guard let activation else { return "noActivation" }
    guard activation.pid == window.app.pid else { return "otherAppActivated" }
    guard activation.workspaceName == focus.workspace.name,
          activation.selectionGeneration == runtime.refresh.workspaceSelectionGeneration
    else { return "activatedFromOtherWorkspace" }
    guard window.isFloating else { return "notFloating" }
    guard let source = window.nodeWorkspace, source !== focus.workspace else { return "alreadyHere" }
    guard !source.isVisible else { return "sourceVisible" }
    return config.followAppActivation.follows(window.app.rawAppBundleId) ? nil : "excludedApp"
}

@MainActor
func ignoresCrossWorkspaceActivation(_ window: Window?) -> Bool {
    guard let window, let workspace = window.nodeWorkspace, workspace !== focus.workspace else { return false }
    return !config.followAppActivation.follows(window.app.rawAppBundleId)
}
