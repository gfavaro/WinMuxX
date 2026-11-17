import AppKit
import Common

@MainActor
func updatePendingWindowDragIntent(sourceWindow: Window, mouseLocation: CGPoint) -> Bool {
    updatePendingWindowDragIntent(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: .window, detachOrigin: .window)
}

@MainActor
func updatePendingWindowDragIntent(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> Bool {
    if detachOrigin != .tabStrip, !getCurrentMouseDragStartedInSidebar() {
        WindowDragCursorProxyPanel.shared.hide()
    }

    guard let destination = currentWindowDragIntentDestination(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    ), isWindowDragIntentKindEnabled(destination.kind) else {
        logWindowDragIntentIfNeeded(
            signature: "drag-live:no-destination:source=\(sourceWindow.windowId):subject=\(debugDescribe(subject)):origin=\(detachOrigin):bucket=\(debugDescribeDragPointBucket(mouseLocation))",
            "[drag-live] destination none source=\(sourceWindow.windowId) subject=\(debugDescribe(subject)) origin=\(detachOrigin) mouse=\(debugDescribe(mouseLocation)) bucket=\(debugDescribeDragPointBucket(mouseLocation)); clearing previews"
        )
        updateSidebarDragFeedback(sourceWindow: sourceWindow, subject: subject, destination: nil)
        clearPendingWindowDragIntent()
        if detachOrigin == .tabStrip || getCurrentMouseDragStartedInSidebar() {
            showWorkspaceSidebarDragCursorPreview(sourceWindow: sourceWindow, subject: subject, point: mouseLocation)
        }
        return false
    }
    updateSidebarDragFeedback(sourceWindow: sourceWindow, subject: subject, destination: destination)
    if detachOrigin == .tabStrip || getCurrentMouseDragStartedInSidebar() {
        showWorkspaceSidebarDragCursorPreview(sourceWindow: sourceWindow, subject: subject, point: mouseLocation)
    }
    return setPendingWindowDragIntent(
        sourceWindowId: sourceWindow.windowId,
        sourceSubject: subject,
        detachOrigin: detachOrigin,
        destination: destination,
    )
}

@MainActor
func refreshPendingWindowDragIntentFromGlobalMouseDrag() {
    WorkspaceSidebarPanel.refreshAll()
    guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .move else {
        clearPendingWindowDragIntent()
        return
    }
    guard let windowId = currentlyManipulatedWithMouseWindowId,
          Window.get(byId: windowId) != nil
    else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    WindowMouseInteractionDriver.shared.noteGlobalDragActivity()
}

@MainActor
func setPendingWindowDragIntent(
    sourceWindowId: UInt32,
    sourceSubject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    destination: WindowDragIntentDestination,
) -> Bool {
    let isPointerSettled = WindowDragFrameGate.shared.state(for: sourceWindowId)?.isSettled ?? false
    WindowTabStripPanelController.shared.clearHiddenPassiveTabGroupChrome()
    updateWindowTabReentryPreview(sourceWindowId: sourceWindowId, destination: destination)
    if let pendingWindowDragIntent,
       pendingWindowDragIntent.sourceWindowId == sourceWindowId,
       pendingWindowDragIntent.sourceSubject == sourceSubject,
       pendingWindowDragIntent.destination.isSameIntent(as: destination)
    {
        return true
    }

    let previousIntent = pendingWindowDragIntent
    pendingWindowDragIntent = PendingWindowDragIntent(
        sourceWindowId: sourceWindowId,
        sourceSubject: sourceSubject,
        destination: destination,
        isPointerSettled: isPointerSettled,
    )
    let signature =
        "intent:source=\(sourceWindowId):subject=\(debugDescribe(sourceSubject)):kind=\(debugDescribe(destination.kind)):preview=\(debugDescribe(destination.previewRect)):interaction=\(debugDescribe(destination.interactionRect))"
    logWindowDragIntentIfNeeded(
        signature: signature,
        "windowDragIntent.update mouse=\(debugDescribe(mouseLocation)) source=\(debugDescribe(Window.get(byId: sourceWindowId))) subject=\(debugDescribe(sourceSubject)) prevKind=\(previousIntent.map { debugDescribe($0.kind) } ?? "nil") prevPreview=\(debugDescribe(previousIntent?.previewRect)) newKind=\(debugDescribe(destination.kind)) newPreview=\(debugDescribe(destination.previewRect)) newInteraction=\(debugDescribe(destination.interactionRect)) style=\(destination.previewStyle) geometry=\(destination.previewGeometry)"
    )
    if let overlay = destination.dropIntentOverlay {
        let activeZone = overlay.activeZone?.rawValue ?? "nil"
        logWindowDragIntentIfNeeded(
            signature: "drag-live:overlay-show:source=\(sourceWindowId):kind=\(debugDescribe(destination.kind)):bucket=\(debugDescribeDragPointBucket(mouseLocation)):zone=\(activeZone)",
            "[drag-live] overlay show request source=\(sourceWindowId) kind=\(debugDescribe(destination.kind)) zone=\(activeZone) target=\(debugDescribe(overlay.targetFrame)) mouse=\(debugDescribe(mouseLocation)) bucket=\(debugDescribeDragPointBucket(mouseLocation))"
        )
        WindowDropIntentOverlayPanelController.shared.show(overlay)
    } else {
        logWindowDragIntentIfNeeded(
            signature: "drag-live:overlay-hide:source=\(sourceWindowId):kind=\(debugDescribe(destination.kind)):bucket=\(debugDescribeDragPointBucket(mouseLocation))",
            "[drag-live] overlay hide request source=\(sourceWindowId) kind=\(debugDescribe(destination.kind)) reason=destination-has-no-overlay mouse=\(debugDescribe(mouseLocation)) bucket=\(debugDescribeDragPointBucket(mouseLocation))"
        )
        WindowDropIntentOverlayPanelController.shared.hide()
    }
    return true
}

@MainActor
func clearPendingWindowDragIntent() {
    let preservesSidebarDragUI = currentActiveWorkspaceSidebarDrag() != nil
    if let pendingWindowDragIntent {
        logWindowDragIntentIfNeeded(
            signature: "intent-cleared:source=\(pendingWindowDragIntent.sourceWindowId):kind=\(debugDescribe(pendingWindowDragIntent.kind))",
            "windowDragIntent.clear mouse=\(debugDescribe(mouseLocation)) source=\(debugDescribe(Window.get(byId: pendingWindowDragIntent.sourceWindowId))) kind=\(debugDescribe(pendingWindowDragIntent.kind)) preview=\(debugDescribe(pendingWindowDragIntent.previewRect))"
        )
    }
    pendingWindowDragIntent = nil
    WindowTabReentryPreviewModel.shared.set(nil)
    WindowTabReentryPreviewModel.shared.setIncoming(nil)
    lastWindowDragIntentLogSignature = nil
    setPinnedDraggedWindowId(nil)
    if !preservesSidebarDragUI {
        setWorkspaceSidebarDropPreviewIfChanged(nil)
    }
    WindowDropIntentOverlayPanelController.shared.hide()
    WindowTabStripPanelController.shared.clearHiddenPassiveTabGroupChrome()
    if !preservesSidebarDragUI {
        WindowDragCursorProxyPanel.shared.hide()
    }
    if getCurrentMouseManipulationKind() == .resize, isLeftMouseButtonDown {
        logWindowDragLive("dragIntent.clear preserving resizePreview during active resize manipulated=\(currentlyManipulatedWithMouseWindowId?.description ?? "nil")")
    } else {
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "dragIntent.clear")
    }
}

@MainActor
private func updateWindowTabReentryPreview(sourceWindowId: UInt32, destination: WindowDragIntentDestination) {
    if windowDragArrangement(for: destination.kind).updateBarDropPreview(sourceWindowId: sourceWindowId, destination: destination) { return }
    WindowTabReentryPreviewModel.shared.setIncoming(nil)
    guard case .reorderTab(let windowId, let targetIndex) = destination.kind,
          windowId == sourceWindowId,
          let sourceWindow = Window.get(byId: sourceWindowId),
          let parent = sourceWindow.parent as? TilingContainer,
          parent.layout == .tabGroup,
          let sourceIndex = sourceWindow.ownIndex
    else {
        WindowTabReentryPreviewModel.shared.set(nil)
        return
    }
    WindowTabReentryPreviewModel.shared.set(WindowTabPendingReorderDrop(
        stripId: ObjectIdentifier(parent),
        windowId: windowId,
        sourceIndex: sourceIndex,
        targetIndex: max(0, min(targetIndex, parent.children.count - 1)),
        orderBeforeDrop: parent.children.compactMap { ($0 as? Window)?.windowId },
        sourceVisualOffset: parent.windowTabDropZoneRect.map {
            tabReentrySourceVisualOffset(
                mouseLocation: MousePointerTracker.shared.currentSample.point,
                tabStripRect: $0,
                tabCount: parent.children.count,
                sourceIndex: sourceIndex
            )
        }
    ))
}

@MainActor
func applyPendingWindowDragIntentIfPossible() -> Bool {
    defer { clearPendingWindowDragIntent() }
    let currentMouseLocation = MousePointerTracker.shared.currentSample.point
    guard let pendingWindowDragIntent,
          let sourceWindow = Window.get(byId: pendingWindowDragIntent.sourceWindowId),
          pendingWindowDragIntent.interactionRect.contains(currentMouseLocation),
          isWindowDragIntentKindEnabled(pendingWindowDragIntent.kind)
    else { return false }
    if let applied = windowDragArrangement(for: pendingWindowDragIntent.kind).applyDrop(
        kind: pendingWindowDragIntent.kind,
        sourceWindow: sourceWindow,
        subject: pendingWindowDragIntent.sourceSubject,
    ) { return applied }
    // The drop's arrangement declined it: the tree's apply takes the rest.
    return TreeWindowDragArrangement.shared.applyDrop(
        kind: pendingWindowDragIntent.kind,
        sourceWindow: sourceWindow,
        subject: pendingWindowDragIntent.sourceSubject,
    ) ?? false
}

/// The windows a drop moves, or nil for an intent that changes nothing.
func windowIdsMovedByDrop(_ kind: WindowDragIntentKind, sourceWindowId: UInt32) -> [UInt32]? {
    switch kind {
        case .reorderTab, .detachTab, .moveToWorkspace, .moveToWorkspaceZone, .createWorkspace: [sourceWindowId]
        case .tabStack(let target), .stackSplit(let target, _), .swap(let target): [sourceWindowId, target]
        case .insertTab, .sidebarHover, .unavailable: nil
    }
}

