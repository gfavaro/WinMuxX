import Foundation

@MainActor
func focusAfterWindowClosure(
    closingWindow: Window,
    focusedWindowIdBeforeClosure: UInt32?,
    deadWindowWorkspace: Workspace?,
    currentFocus: LiveFocus,
    previousFocus: LiveFocus?,
    previousPreviousFocus: LiveFocus?,
    refreshSnapshotCloseFallback: LiveFocus?,
    refreshSnapshotPreviousFocus: LiveFocus?,
    refreshSnapshotPreviousPreviousFocus: LiveFocus?,
    previousFocusedWorkspace: Workspace?,
    previousFocusedWorkspaceDate: Date,
    now: Date = .now,
) -> LiveFocus? {
    guard let deadWindowWorkspace else { return nil }
    // Only closing the focused window may move focus. A window the user never focused
    // (a short-lived viewer, a dialog an app or agent opens and closes) used to reach the
    // history fallbacks below and pull focus to an older window, often another app.
    // From WinMux PR #32 by Ilya Kudravets.
    guard focusedWindowIdBeforeClosure == closingWindow.windowId else {
        debugFocusLog("focusAfterWindowClosure closing=\(closingWindow.windowId) skippedNotFocused focusedBefore=\(focusedWindowIdBeforeClosure?.description ?? "nil")")
        return nil
    }
    guard deadWindowWorkspace == currentFocus.workspace ||
        deadWindowWorkspace == previousFocusedWorkspace && previousFocusedWorkspaceDate.distance(to: now) < 1
    else {
        debugFocusLog("focusAfterWindowClosure closing=\(closingWindow.windowId) skipped currentFocus=\(debugDescribe(currentFocus)) previousFocusedWorkspace=\(previousFocusedWorkspace?.name ?? "nil")")
        return nil
    }

    let replacement = FocusAfterWindowClosureReplacement(closingWindow: closingWindow, deadWindowWorkspace: deadWindowWorkspace)
    if let snapshotTabFocus = replacement.snapshotTabGroupFocus(
        closeFallback: refreshSnapshotCloseFallback,
        previousFocus: refreshSnapshotPreviousFocus,
        previousPreviousFocus: refreshSnapshotPreviousPreviousFocus,
        currentFocus: currentFocus,
    ) {
        return snapshotTabFocus
    }

    if replacement.shouldPreferSnapshotCloseFallback(
        closeFallback: refreshSnapshotCloseFallback,
        currentFocus: currentFocus,
        previousFocus: refreshSnapshotPreviousFocus,
    ) {
        debugFocusLog(
            "focusAfterWindowClosure closing=\(closingWindow.windowId) preferSnapshotCloseFallback=\(debugDescribe(refreshSnapshotCloseFallback)) current=\(debugDescribe(currentFocus)) snapshotPrev=\(debugDescribe(refreshSnapshotPreviousFocus))"
        )
        return refreshSnapshotCloseFallback
    }

    let fallbackHistory: [LiveFocus?] = [
        refreshSnapshotCloseFallback,
        refreshSnapshotPreviousFocus,
        previousFocus,
        (refreshSnapshotPreviousFocus?.windowOrNil == closingWindow) ? refreshSnapshotPreviousPreviousFocus : nil,
        (previousFocus?.windowOrNil == closingWindow) ? previousPreviousFocus : nil,
    ]
    for candidate in fallbackHistory where replacement.isValid(candidate) {
        debugFocusLog(
            "focusAfterWindowClosure closing=\(closingWindow.windowId) choseCandidate=\(debugDescribe(candidate)) current=\(debugDescribe(currentFocus)) snapshotCloseFallback=\(debugDescribe(refreshSnapshotCloseFallback)) snapshotPrev=\(debugDescribe(refreshSnapshotPreviousFocus)) snapshotPrevPrev=\(debugDescribe(refreshSnapshotPreviousPreviousFocus)) prev=\(debugDescribe(previousFocus)) prevPrev=\(debugDescribe(previousPreviousFocus))"
        )
        return candidate
    }

    let fallback = deadWindowWorkspace.toLiveFocus()
    debugFocusLog("focusAfterWindowClosure closing=\(closingWindow.windowId) defaultFallback=\(debugDescribe(fallback))")
    return fallback
}
