@MainActor
func updateDetachedTabFromTabStrip(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    // A side-by-side tab of a Tabbed workspace is one entry in the bar: it leaves as a whole.
    let isSideBySideTab = window.nodeWorkspace.map { $0.arrangement == .tabbed && $0.tabbedUnit(containing: window) is TilingContainer } == true
    startTabStripWindowMove(window: window, subject: isSideBySideTab ? .group : .window, detachOrigin: .tabStrip)
}

@MainActor
func updateMoveFromTabStrip(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    if shouldDeferWindowTabStripGroupDragToDetachedTabDrag() {
        return
    }
    startTabStripWindowMove(window: window, subject: .group, detachOrigin: .tabStrip)
}

@MainActor
func finishMoveFromTabStrip() {
    guard shouldHandleWindowTabStripGroupDragEnd() else { return }
    Task { @MainActor in
        try? await resetManipulatedWithMouseIfPossible()
    }
}

@MainActor
private func startTabStripWindowMove(window: Window, subject: WindowDragSubject, detachOrigin: TabDetachOrigin) {
    beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: subject,
        detachOrigin: detachOrigin,
        startedInSidebar: false,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: subject),
        refreshActualRects: true,
    )
    WindowMouseInteractionDriver.shared.startMove(
        windowId: window.windowId,
        subject: subject,
        detachOrigin: detachOrigin,
        startedInSidebar: false,
    )
}
