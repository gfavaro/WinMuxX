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
    guard let host = workspace.tabbedGroup(containing: targetWindow.windowId)?.barGroup, let area = host.lastFrame,
          area.contains(mouseLocation) else { return nil }
    if subject == .window, let bar = tabbedBarDropDestination(host: host, area: area, sourceWindow: sourceWindow,
                                                               targetWindow: targetWindow, mouseLocation: mouseLocation) {
        return bar
    }
    guard let zone = WindowIntentZoneBuilder.zone(at: mouseLocation, in: area) else { return nil }
    let resolution = WindowDropIntentResolution(
        intent: WindowDropIntent(sourceWindowId: sourceWindow.windowId, targetWindowId: targetWindow.windowId, zone: zone),
        targetFrame: area,
        targetCornerRadius: nil,
        zones: WindowIntentZoneBuilder.zones(in: area),
    )
    return destinationFromWindowDropIntent(resolution, sourceWindow: sourceWindow, targetWindow: targetWindow,
                                           mouseLocation: mouseLocation, subject: subject, detachOrigin: detachOrigin)
}

/// Notes how far the Tabbed workspace bar `stripId` has scrolled its tabs.
@MainActor
func recordWorkspaceTabBarScroll(_ stripId: ObjectIdentifier, contentMinX: CGFloat) {
    for workspace in Workspace.all where workspace.arrangement == .tabbed {
        if let group = workspace.tabbedGroups.first(where: { ObjectIdentifier($0) == stripId }) {
            group.barScrollOffset = contentMinX
            return
        }
    }
}

/// Where a tab group's tabs sit on screen: the bar across the top of its area, as its strip lays
/// them out and has scrolled them.
@MainActor
func tabbedBarTabsRect(area: Rect, host: TabbedGroup? = nil) -> Rect {
    let scrolled = host?.barScrollOffset ?? 0
    return Rect(topLeftX: area.topLeftX + windowTabStripLeadingInset + scrolled, topLeftY: area.topLeftY,
                width: workspaceTabBarTabsStripWidth(area.width), height: min(resolvedWindowTabBarHeight(), area.height))
}

/// Over a Tabbed workspace's bar a tab goes where the pointer is among its tabs: back along its
/// own bar, or into another bar at that place, as the strip shows by opening a gap there.
@MainActor
private func tabbedBarDropDestination(
    host: TabbedGroup,
    area: Rect,
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
) -> WindowDragIntentDestination? {
    let tabs = tabbedBarTabsRect(area: area, host: host)
    let interaction = Rect(topLeftX: area.topLeftX, topLeftY: area.topLeftY, width: area.width, height: tabs.height + 8)
    guard interaction.contains(mouseLocation) else { return nil }
    let bar = host.barWindowIds
    let kind: WindowDragIntentKind
    if let sourceIndex = bar.firstIndex(of: sourceWindow.windowId) {
        guard bar.count > 1 else { return nil }
        kind = .reorderTab(windowId: sourceWindow.windowId, targetIndex: tabReentryTargetIndex(
            mouseLocation: mouseLocation, tabStripRect: tabs, tabCount: bar.count, sourceIndex: sourceIndex,
            minimumTabWidth: workspaceTabStripMinimumTabWidth))
    } else {
        kind = .insertTab(targetWindowId: targetWindow.windowId, index: tabInsertionSlot(
            mouseLocation: mouseLocation, tabStripRect: tabs, tabCount: bar.count, minimumTabWidth: workspaceTabStripMinimumTabWidth))
    }
    let moves = if case .insertTab = kind { true } else { false }
    return WindowDragIntentDestination(
        kind: kind,
        previewRect: tabbedBarTabsRect(area: area),
        interactionRect: interaction,
        title: moves ? "Move to Tab Group" : "Move Tab",
        subtitle: moves ? "Drop to add this tab here" : "Drop to put this tab back here",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
        dropIntentOverlay: WindowDropIntentOverlayModel(targetFrame: area, activeZone: .tab, cornerRadius: nil),
    )
}
