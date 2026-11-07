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
       pendingWindowDragIntent.kind == destination.kind,
       pendingWindowDragIntent.title == destination.title,
       pendingWindowDragIntent.subtitle == destination.subtitle,
       pendingWindowDragIntent.previewStyle == destination.previewStyle,
       pendingWindowDragIntent.previewGeometry == destination.previewGeometry,
       pendingWindowDragIntent.isGroup == destination.isGroup,
       pendingWindowDragIntent.previewRect.isEqual(to: destination.previewRect),
       pendingWindowDragIntent.interactionRect.isEqual(to: destination.interactionRect)
    {
        return true
    }

    let previousIntent = pendingWindowDragIntent
    pendingWindowDragIntent = PendingWindowDragIntent(
        sourceWindowId: sourceWindowId,
        sourceSubject: sourceSubject,
        kind: destination.kind,
        previewRect: destination.previewRect,
        interactionRect: destination.interactionRect,
        title: destination.title,
        subtitle: destination.subtitle,
        previewStyle: destination.previewStyle,
        previewGeometry: destination.previewGeometry,
        isGroup: destination.isGroup,
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
    if let applied = applyTabbedGroupDragIntent(pendingWindowDragIntent.kind, sourceWindow: sourceWindow,
                                                subject: pendingWindowDragIntent.sourceSubject) { return applied }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: pendingWindowDragIntent.sourceSubject)
    switch pendingWindowDragIntent.kind {
        case .reorderTab(let windowId, let targetIndex):
            guard pendingWindowDragIntent.sourceSubject == .window,
                  sourceWindow.windowId == windowId
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId])
            return reorderWindowTabInCurrentGroup(sourceWindow, toIndex: targetIndex)
        case .tabStack(let targetWindowId):
            guard pendingWindowDragIntent.sourceSubject == .window else { return false }
            guard let targetWindow = Window.get(byId: targetWindowId),
                  sourceWindow != targetWindow
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId, targetWindow.windowId])
            createOrAppendWindowTabStack(sourceWindow: sourceWindow, onto: targetWindow, newGroupLayout: .tabGroup)
            return true
        case .detachTab(let windowId):
            guard sourceWindow.windowId == windowId else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId])
            return removeWindowFromTabStack(sourceWindow)
        case .stackSplit(let targetWindowId, let position):
            guard let targetWindow = Window.get(byId: targetWindowId)
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId, targetWindow.windowId])
            return applyWindowStackSplitDragIntent(
                sourceWindow: sourceWindow,
                sourceSubject: pendingWindowDragIntent.sourceSubject,
                targetWindow: targetWindow,
                position: position,
            )
        case .swap(let targetWindowId):
            guard let targetWindow = Window.get(byId: targetWindowId)
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId, targetWindow.windowId])
            return applyWindowSwapDragIntent(
                sourceWindow: sourceWindow,
                sourceSubject: pendingWindowDragIntent.sourceSubject,
                targetWindow: targetWindow,
            )
        case .moveToWorkspace(let workspaceName):
            guard let targetWorkspace = Workspace.existing(byName: workspaceName) else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId])
            if pendingWindowDragIntent.previewStyle == .sidebarWorkspaceMove {
                applySidebarWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, targetWorkspace: targetWorkspace)
            } else {
                applyWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, mouseLocation: mouseLocation, targetWorkspace: targetWorkspace)
            }
            return true
        case .moveToWorkspaceZone(let workspaceName, let zone):
            guard let targetWorkspace = Workspace.existing(byName: workspaceName) else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId])
            applyWorkspaceZoneMove(sourceNode: sourceNode, sourceWindow: sourceWindow, targetWorkspace: targetWorkspace, zone: zone)
            return true
        case .createWorkspace(let projectId, let monitorScopeId):
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId])
            return createWorkspaceFromSidebarDrag(
                sourceNode: sourceNode,
                sourceWindow: sourceWindow,
                projectId: projectId,
                monitorScopeId: monitorScopeId,
            )
        case .sidebarHover:
            return false
    }
}

/// Dropping a window on a Tabbed workspace's window: on an edge it opens a new tab group on that
/// side, in the middle or on the tabs it joins that window's group. Nil when the drop does not
/// land on a Tabbed workspace's tab group.
@MainActor
func applyTabbedGroupDragIntent(_ kind: WindowDragIntentKind, sourceWindow: Window, subject: WindowDragSubject = .window) -> Bool? {
    guard let (targetId, side) = tabbedGroupDropTarget(kind),
          let target = Window.get(byId: targetId), let workspace = target.nodeWorkspace, workspace.arrangement == .tabbed,
          sourceWindow !== target || side != nil, workspace.tabbedGroup(containing: targetId) != nil else { return nil }
    syncClosedWindowsCacheToCurrentWorld()
    suppressPostDragAxObserverEvents(for: [sourceWindow.windowId, target.windowId])
    var windowIds = [sourceWindow.windowId]
    if workspace.tabbedGroup(containing: sourceWindow.windowId) == nil {
        // A floating window, or windows from elsewhere, first join the tree beside the target, kept
        // for the other arrangements, and then become tabs where they were dropped.
        let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
        let windows = sourceNode.allLeafWindowsRecursive
        guard let parent = target.parent as? TilingContainer, !windows.contains(where: { $0 === target }) else { return false }
        sourceNode.unbindFromParent()
        sourceNode.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: (target.ownIndex ?? parent.children.count - 1) + 1)
        workspace.syncTabbedGroups()
        windowIds = [sourceWindow.windowId] + windows.map(\.windowId).filter { $0 != sourceWindow.windowId }
    }
    // An imported window may already have joined the target's group as a newcomer.
    guard let group = workspace.tabbedGroup(containing: targetId),
          side.map({ workspace.moveTabbedTabToNewGroup(sourceWindow.windowId, beside: group, on: $0) })
            ?? (workspace.tabbedGroup(containing: sourceWindow.windowId) === group
                || workspace.moveTabbedTab(sourceWindow.windowId, into: group)),
          let destination = workspace.tabbedGroup(containing: sourceWindow.windowId) else { return false }
    for windowId in windowIds.dropFirst() { _ = workspace.moveTabbedTab(windowId, into: destination) }
    destination.activeWindowId = sourceWindow.windowId
    _ = sourceWindow.focusWindow()
    return true
}

/// The window a drop lands on and, for an edge, the side a new tab group opens on.
func tabbedGroupDropTarget(_ kind: WindowDragIntentKind) -> (UInt32, CardinalDirection?)? {
    switch kind {
        case .stackSplit(let target, let position):
            let side: CardinalDirection = switch position {
                case .left: .left
                case .right: .right
                case .above: .up
                case .below: .down
            }
            return (target, side)
        case .tabStack(let target), .swap(let target): return (target, nil)
        default: return nil
    }
}
