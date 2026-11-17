import AppKit
import Common

/// The Tabbed arrangement's drag stages. Its drops resolve from the tab groups on screen,
/// never from the tree kept beneath them.
@MainActor
final class TabbedWindowDragArrangement: WindowDragArrangement {
    static let shared = TabbedWindowDragArrangement()
    private init() {}

    func surfaceDestination(
        sourceWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination? {
        // The window shown by the tab group under the pointer, its bar included.
        let workspace = mouseLocation.monitorApproximation.activeWorkspace
        guard let target = workspace.tabbedGroups.first(where: { $0.lastFrame?.contains(mouseLocation) == true })?.displayedWindow
        else { return nil }
        return tabbedWindowSurfaceDestination(in: workspace, sourceWindow: sourceWindow, targetWindow: target,
                                              mouseLocation: mouseLocation, subject: subject, detachOrigin: detachOrigin)
    }

    func windowDestination(
        sourceWindow: Window,
        targetWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination? {
        guard let workspace = targetWindow.nodeWorkspace else { return nil }
        return tabbedWindowSurfaceDestination(in: workspace, sourceWindow: sourceWindow, targetWindow: targetWindow,
                                              mouseLocation: mouseLocation, subject: subject, detachOrigin: detachOrigin)
    }

    func dropIntentDestination(
        resolution: WindowDropIntentResolution,
        sourceWindow: Window,
        targetWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination? {
        // A drop on a Tabbed workspace's window lands in its tab groups, which are kept apart from
        // the tree, so the tree's own containers have no say.
        let source = targetWindow.nodeWorkspace?.tabbedGroup(containing: sourceWindow.windowId)
        return tabbedGroupDropDestination(resolution, source: source, sourceWindow: sourceWindow, targetWindow: targetWindow,
                                          subject: subject)
    }

    func updateBarDropPreview(sourceWindowId: UInt32, destination: WindowDragIntentDestination) -> Bool {
        let preview = WindowTabReentryPreviewModel.shared
        let mouse = MousePointerTracker.shared.currentSample.point
        switch destination.kind {
            case .insertTab(let targetWindowId, let index):
                guard let workspace = Window.get(byId: targetWindowId)?.nodeWorkspace,
                      let host = workspace.tabbedGroup(containing: targetWindowId)?.barGroup else { return false }
                preview.set(nil)
                preview.setIncoming(WindowTabIncomingDrop(stripId: ObjectIdentifier(host), targetIndex: index,
                                                          orderBeforeDrop: host.barWindowIds))
                return true
            case .reorderTab(let windowId, let targetIndex):
                guard windowId == sourceWindowId, let workspace = Window.get(byId: windowId)?.nodeWorkspace,
                      workspace.arrangement == .tabbed, let host = workspace.tabbedGroup(containing: windowId)?.barGroup,
                      let area = host.lastFrame else { return false }
                let bar = host.barWindowIds
                guard let sourceIndex = bar.firstIndex(of: windowId) else { return false }
                preview.setIncoming(nil)
                preview.set(WindowTabPendingReorderDrop(
                    stripId: ObjectIdentifier(host),
                    windowId: windowId,
                    sourceIndex: sourceIndex,
                    targetIndex: max(0, min(targetIndex, bar.count - 1)),
                    orderBeforeDrop: bar,
                    sourceVisualOffset: tabReentrySourceVisualOffset(mouseLocation: mouse, tabStripRect: tabbedBarTabsRect(area: area, host: host),
                                                                     tabCount: bar.count, sourceIndex: sourceIndex,
                                                                     minimumTabWidth: workspaceTabStripMinimumTabWidth),
                ))
                return true
            default:
                return false
        }
    }

    func applyDrop(kind: WindowDragIntentKind, sourceWindow: Window, subject: WindowDragSubject) -> Bool? {
        // A drop onto a Tabbed workspace's tab group first; nil leaves the drop to the tree's apply.
        if let applied = applyTabbedGroupDragIntent(kind, sourceWindow: sourceWindow, subject: subject) { return applied }
        // A tab dropped back onto the bar of the Tabbed workspace it came from moves along that
        // bar. Without its group on screen, or for another kind, the tree's apply takes over.
        guard case .reorderTab(let windowId, let targetIndex) = kind else { return nil }
        guard subject == .window, sourceWindow.windowId == windowId else { return false }
        guard let workspace = sourceWindow.nodeWorkspace, workspace.arrangement == .tabbed,
              let group = workspace.tabbedGroup(containing: windowId)
        else { return nil }
        syncClosedWindowsCacheToCurrentWorld()
        suppressPostDragAxObserverEvents(for: [sourceWindow.windowId])
        guard workspace.insertTabbedTab(windowId, intoBarOf: group.barGroup, at: targetIndex) else { return false }
        return sourceWindow.focusWindow()
    }
}

/// Dropping a window on a Tabbed workspace's window: on an edge it opens a new tab group on that
/// side, in the middle it joins that window's group, and on the bar it goes where it was dropped
/// among the tabs. Nil when the drop does not land on a Tabbed workspace's tab group.
@MainActor
func applyTabbedGroupDragIntent(_ kind: WindowDragIntentKind, sourceWindow: Window, subject: WindowDragSubject = .window) -> Bool? {
    guard let (targetId, side) = tabbedGroupDropTarget(kind),
          let target = Window.get(byId: targetId), let workspace = target.nodeWorkspace, workspace.arrangement == .tabbed,
          sourceWindow !== target || side != nil, workspace.tabbedGroup(containing: targetId) != nil else { return nil }
    syncClosedWindowsCacheToCurrentWorld()
    suppressPostDragAxObserverEvents(for: [sourceWindow.windowId, target.windowId])
    let insertIndex: Int? = if case .insertTab(_, let index) = kind { index } else { nil }
    var windowIds = [sourceWindow.windowId]
    var importedGroupOrder: [UInt32] = []
    if workspace.tabbedGroup(containing: sourceWindow.windowId) == nil {
        // A floating window, or windows from elsewhere, first join the tree beside the target, kept
        // for the other arrangements, and then become tabs where they were dropped.
        // Another Tabbed workspace's handle carries its tab group, which the tree does not hold.
        let windows: [Window], nodes: [TreeNode]
        if subject == .group, let from = sourceWindow.nodeWorkspace, from.arrangement == .tabbed,
           let group = from.tabbedGroup(containing: sourceWindow.windowId) {
            windows = group.shownWindowIds.compactMap { Window.get(byId: $0) }
            nodes = windows
            // Its minimized, hidden or fullscreen tabs come too, staying as they are, all in order.
            importedGroupOrder = group.windowIds
            let retainedIds = group.windowIds.filter { id in !windows.contains { $0.windowId == id } }
            group.windowIds.removeAll { retainedIds.contains($0) }
            for id in retainedIds { Window.get(byId: id)?.transferRetainedTabbedState(to: workspace) }
        } else {
            let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
            windows = sourceNode.allLeafWindowsRecursive
            nodes = [sourceNode]
        }
        guard let parent = target.parent as? TilingContainer, !windows.contains(where: { $0 === target }) else { return false }
        var index = (target.ownIndex ?? parent.children.count - 1) + 1
        for node in nodes {
            node.unbindFromParent()
            node.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: index)
            index += 1
        }
        workspace.syncTabbedGroups()
        windowIds = [sourceWindow.windowId] + windows.map(\.windowId).filter { $0 != sourceWindow.windowId }
    } else if subject == .group, let source = workspace.tabbedGroup(containing: sourceWindow.windowId),
              let group = workspace.tabbedGroup(containing: targetId)?.barGroup {
        // A group's handle carries the whole group: beside another group, or into it.
        guard side.map({ workspace.moveTabbedGroup(source, beside: group, on: $0) })
            ?? workspace.mergeTabbedGroup(source, into: group) else { return false }
        _ = sourceWindow.focusWindow()
        return true
    }
    // An imported window may already have joined the target's group as a newcomer.
    guard let group = workspace.tabbedGroup(containing: targetId)?.barGroup,
          side.map({ workspace.moveTabbedTabToNewGroup(sourceWindow.windowId, beside: group, on: $0) })
            ?? insertIndex.map({ workspace.insertTabbedTab(sourceWindow.windowId, intoBarOf: group, at: $0) })
            ?? (workspace.tabbedGroup(containing: sourceWindow.windowId) === group
                || workspace.moveTabbedTab(sourceWindow.windowId, into: group)),
          let destination = workspace.tabbedGroup(containing: sourceWindow.windowId) else { return false }
    for windowId in windowIds.dropFirst() { _ = workspace.moveTabbedTab(windowId, into: destination) }
    if !importedGroupOrder.isEmpty {
        destination.windowIds = destination.windowIds.filter { !importedGroupOrder.contains($0) } + importedGroupOrder
    }
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
        case .tabStack(let target), .insertTab(let target, _), .swap(let target): return (target, nil)
        default: return nil
    }
}

/// The tabs of the Tabbed group `window` shows, in bar order, with the workspace holding them.
@MainActor
func tabbedGroupCarried(by window: Window) -> (workspace: Workspace, windowIds: [UInt32])? {
    guard let workspace = window.nodeWorkspace, workspace.arrangement == .tabbed,
          let group = workspace.tabbedGroup(containing: window.windowId), group.windowIds.count > 1 else { return nil }
    return (workspace, group.windowIds)
}

/// Once the window a group's handle dragged has gone to another workspace, the rest of its tab
/// group follows, keeping its order; minimized, hidden and fullscreen tabs stay as they are.
@MainActor
func bringTabbedGroupAlong(_ carried: (workspace: Workspace, windowIds: [UInt32]), after window: Window) {
    guard let target = window.nodeWorkspace, target !== carried.workspace else { return }
    let parent = window.parent as? TilingContainer ?? target.rootTilingContainer
    var index = window.parent === parent ? (window.ownIndex ?? parent.children.count - 1) + 1 : INDEX_BIND_LAST
    for id in carried.windowIds where id != window.windowId {
        guard let other = Window.get(byId: id), other.nodeWorkspace === carried.workspace || other.nodeWorkspace == nil else { continue }
        if other.parent is TilingContainer {
            other.unbindFromParent()
            other.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: index)
            if index != INDEX_BIND_LAST { index += 1 }
        } else {
            other.transferRetainedTabbedState(to: target)
        }
    }
    carried.workspace.tabbedGroups.forEach { $0.windowIds.removeAll { carried.windowIds.contains($0) } }
    carried.workspace.tabbedState.layout = carried.workspace.tabbedState.layout?.pruned()
    guard target.arrangement == .tabbed else { return }
    target.syncTabbedGroups()
    guard let group = target.tabbedGroup(containing: window.windowId) else { return }
    for other in target.tabbedGroups where other !== group { other.windowIds.removeAll { carried.windowIds.contains($0) } }
    group.windowIds = group.windowIds.filter { !carried.windowIds.contains($0) } + carried.windowIds
    group.activeWindowId = window.windowId
    target.tabbedState.layout = target.tabbedState.layout?.pruned()
}

/// A drop on the area of the tab group showing `targetWindow`, its bar included. The tab shown
/// may be the one dragged: an edge then opens a new group beside its own.
@MainActor
private func tabbedWindowSurfaceDestination(
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

/// The middle or top of a window moves the tab into its group; an edge opens a new group on that side.
@MainActor
private func tabbedGroupDropDestination(
    _ resolution: WindowDropIntentResolution,
    source: TabbedGroup?,
    sourceWindow: Window,
    targetWindow: Window,
    subject: WindowDragSubject,
) -> WindowDragIntentDestination? {
    guard let workspace = targetWindow.nodeWorkspace,
          let target = workspace.tabbedGroup(containing: targetWindow.windowId)?.barGroup else { return nil }
    // A group's handle carries the whole group, which has nowhere to go beside or into itself.
    let carriesGroup = subject == .group && source != nil
    if carriesGroup, target === source?.barGroup { return nil }
    // Edges where the windows would have no room side by side or stacked are marked as such, as
    // the bar's split buttons are; the new group would only fold back into a bar.
    let splitsAt: [(WindowDropZone, CardinalDirection)] = [(.left, .left), (.right, .right), (.top, .up), (.bottom, .down)]
    // A group's handle moves every tab of the group.
    let moving = carriesGroup ? source?.windowIds ?? [sourceWindow.windowId] : [sourceWindow.windowId]
    let blockers: [WindowDropZone: String] = target === source?.barGroup && target.barWindowIds.count < 2 ? [:]
        : Dictionary(uniqueKeysWithValues: splitsAt.compactMap { zone, side in
            workspace.tabbedSplitBlocker(placing: moving, beside: target, on: side).map { (zone, $0) }
        })
    let kind: WindowDragIntentKind
    switch resolution.intent.zone {
        case .tab, .middle:
            guard target !== source?.barGroup else { return nil }
            kind = .tabStack(targetWindowId: targetWindow.windowId)
        case .left, .right, .top, .bottom:
            // A group's only tab beside itself would change nothing.
            guard let position = resolution.intent.zone.stackSplitPosition,
                  target !== source?.barGroup || target.barWindowIds.count > 1 else { return nil }
            kind = blockers[resolution.intent.zone] == nil ? .stackSplit(targetWindowId: targetWindow.windowId, position: position) : .unavailable
    }
    let joins = if case .tabStack = kind { true } else { false }
    let preview = windowDropIntentActivePreviewRect(for: resolution)
    return WindowDragIntentDestination(
        kind: kind,
        previewRect: preview,
        interactionRect: resolution.targetFrame,
        title: carriesGroup ? (joins ? "Merge Tab Groups" : "Move Tab Group") : (joins ? "Move to Tab Group" : "New Tab Group"),
        subtitle: carriesGroup
            ? (joins ? "Drop to add all these tabs to that group" : "Drop to move the whole group to this side")
            : (joins ? "Drop to add this tab to that group" : "Drop to open the tab in a new group on this side"),
        previewStyle: joins ? .tabInsert : .stackSplit,
        previewGeometry: joins ? .tabStrip : .rounded,
        isGroup: subject == .group,
        dropIntentOverlay: WindowDropIntentOverlayModel(targetFrame: resolution.targetFrame, activeZone: resolution.intent.zone,
                                                        cornerRadius: nil, unavailableZones: Array(blockers.keys),
                                                        unavailableReason: blockers[resolution.intent.zone]),
    )
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
