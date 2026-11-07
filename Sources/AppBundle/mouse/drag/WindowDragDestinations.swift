import AppKit

@MainActor
func windowSurfaceDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if let workspace = tabbedDragWorkspace(sourceWindow: sourceWindow, targetWorkspace: targetWindow.nodeWorkspace) {
        return tabbedWindowSurfaceDestination(in: workspace, sourceWindow: sourceWindow, targetWindow: targetWindow,
                                              mouseLocation: mouseLocation, subject: subject, detachOrigin: detachOrigin)
    }
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin,
    )
    if let reentryDestination = selfTabGroupTabReentryDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    ) {
        return reentryDestination
    }
    let resolvedIntent = resolveWindowDropIntent(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        targetNode: targetNode,
        mouseLocation: mouseLocation,
    )
    if detachOrigin == .tabStrip,
       subject == .window,
       let sourceParent = sourceWindow.parent as? TilingContainer,
       sourceParent.layout == .tabGroup,
       targetWindow.parent === sourceParent
    {
        logWindowDragHitTestIfNeeded(
            signature: "self-tab-group-intent:source=\(sourceWindow.windowId):target=\(targetWindow.windowId):intent=\(resolvedIntent?.intent.zone.rawValue ?? "nil")",
            "windowDragTarget.selfTabGroupIntent mouse=\(debugDescribe(mouseLocation)) source=\(debugDescribe(sourceWindow)) target=\(debugDescribe(targetWindow)) targetNode=\(debugDescribe(targetNode)) visible=\(debugDescribe(targetNode.windowDragVisibleRect)) resolved=\(resolvedIntent?.intent.zone.rawValue ?? "nil")"
        )
    }

    guard let resolvedIntent else { return nil }
    return destinationFromWindowDropIntent(
        resolvedIntent,
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    )
}

/// The Tabbed workspace a drag lands on: its drops are resolved from the tab groups on screen,
/// never from the tree kept beneath them.
@MainActor
func tabbedDragWorkspace(sourceWindow _: Window, targetWorkspace: Workspace?) -> Workspace? {
    guard let workspace = targetWorkspace, workspace.arrangement == .tabbed else { return nil }
    return workspace
}

/// A drop on the area of the tab group showing `targetWindow`, its bar included. The tab shown
/// may be the one dragged: an edge then opens a new group beside its own.
@MainActor
func tabbedWindowSurfaceDestination(
    in workspace: Workspace,
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard let area = workspace.tabbedGroup(containing: targetWindow.windowId)?.barGroup.lastFrame, area.contains(mouseLocation),
          let zone = WindowIntentZoneBuilder.zone(at: mouseLocation, in: area) else { return nil }
    let resolution = WindowDropIntentResolution(
        intent: WindowDropIntent(sourceWindowId: sourceWindow.windowId, targetWindowId: targetWindow.windowId, zone: zone),
        targetFrame: area,
        targetCornerRadius: nil,
        zones: WindowIntentZoneBuilder.zones(in: area),
    )
    return destinationFromWindowDropIntent(resolution, sourceWindow: sourceWindow, targetWindow: targetWindow,
                                           mouseLocation: mouseLocation, subject: subject, detachOrigin: detachOrigin)
}
