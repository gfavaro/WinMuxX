import Common
import Foundation

@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

@MainActor private struct WorkspaceProjectFocusHold {
    let projectId: WorkspaceProjectId
    let expiresAt: Date
}

@MainActor private var workspaceProjectFocusHold: WorkspaceProjectFocusHold? = nil

@MainActor private struct WindowClosureFocusHold {
    let workspaceId: WorkspaceId
    let appPid: Int32
    let expiresAt: Date
}

@MainActor private var windowClosureFocusHold: WindowClosureFocusHold?

@MainActor
func holdFocusAfterLastWindowClosure(on workspace: Workspace, appPid: Int32, now: Date = .now) {
    windowClosureFocusHold = WindowClosureFocusHold(workspaceId: workspace.id, appPid: appPid, expiresAt: now.addingTimeInterval(0.25))
}

@MainActor
private func shouldIgnoreNativeFocusAfterWindowClosure(_ nativeFocused: Window?, now: Date) -> Bool {
    guard let hold = windowClosureFocusHold else { return false }
    guard now < hold.expiresAt, focus.workspace.id == hold.workspaceId else {
        windowClosureFocusHold = nil
        return false
    }
    guard let nativeFocused, let workspace = nativeFocused.visualWorkspace else { return false }
    // Closing the final document can make macOS promote another document of
    // the same app, even when it is parked in an inactive workspace.
    return nativeFocused.app.pid == hold.appPid && workspace.id != hold.workspaceId && !workspace.isVisible
}

@MainActor
func resetFocusCacheForTests() {
    lastKnownNativeFocusedWindowId = nil
    workspaceProjectFocusHold = nil
    windowClosureFocusHold = nil
}

@MainActor
func holdFocusOnWorkspaceProject(_ projectId: WorkspaceProjectId, for duration: TimeInterval) {
    workspaceProjectFocusHold = WorkspaceProjectFocusHold(
        projectId: projectId,
        expiresAt: Date().addingTimeInterval(duration),
    )
}

@MainActor
func clearFocusOnWorkspaceProjectHold(_ projectId: WorkspaceProjectId? = nil) {
    guard projectId == nil || workspaceProjectFocusHold?.projectId == projectId else { return }
    workspaceProjectFocusHold = nil
}

@MainActor
private func activeWorkspaceProjectFocusHold(now: Date = .now) -> WorkspaceProjectFocusHold? {
    guard let hold = workspaceProjectFocusHold else { return nil }
    if hold.expiresAt <= now {
        workspaceProjectFocusHold = nil
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
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?, now: Date = .now) {
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    let lastKnownNativeFocusedWindowIdBefore = lastKnownNativeFocusedWindowId
    if shouldIgnoreNativeFocusAfterWindowClosure(nativeFocused, now: now) {
        lastKnownNativeFocusedWindowId = nil
        debugFocusLog("updateFocusCache ignoredWindowClosure nativeFocused=\(nativeFocused?.windowId.description ?? "nil") logicalFocus=\(debugDescribe(focus))")
        return
    }
    if shouldIgnoreNativeFocusDuringProjectHold(nativeFocused) {
        lastKnownNativeFocusedWindowId = nil
        debugFocusLog(
            "updateFocusCache ignoredProjectHold event=\(refreshSessionEvent.prettyDescription) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") lastKnownNative=\(lastKnownNativeFocusedWindowIdBefore?.description ?? "nil") heldProject=\(activeWorkspaceProjectFocusHold()?.projectId.rawValue ?? "nil") logicalFocus=\(debugDescribe(focus))"
        )
        return
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        _ = nativeFocused?.focusWindow()
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    (nativeFocused?.app as? MacApp)?.lastNativeFocusedWindowId = nativeFocused?.windowId
    debugFocusLog(
        "updateFocusCache event=\(refreshSessionEvent.prettyDescription) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") lastKnownNative=\(lastKnownNativeFocusedWindowIdBefore?.description ?? "nil") -> \(lastKnownNativeFocusedWindowId?.description ?? "nil") logicalFocus=\(debugDescribe(focus))"
    )
}
