import Common
import CoreGraphics

@MainActor
func destinationFromWindowDropIntent(
    _ resolution: WindowDropIntentResolution,
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    func intentOverlayDestination(_ destination: WindowDragIntentDestination) -> WindowDragIntentDestination {
        var result = destination
        result.previewRect = windowDropIntentActivePreviewRect(for: resolution)
        result.interactionRect = resolution.targetFrame
        result.dropIntentOverlay = WindowDropIntentOverlayModel(
            targetFrame: resolution.targetFrame,
            activeZone: resolution.intent.zone,
            cornerRadius: resolution.targetCornerRadius.map(CGFloat.init),
            unavailableZones: destination.dropIntentOverlay?.unavailableZones ?? [],
            unavailableReason: destination.dropIntentOverlay?.unavailableReason,
        )
        return result
    }

    // A drop on a Tabbed workspace's window lands in its tab groups, which are kept apart from
    // the tree, so the tree's own containers have no say.
    if let workspace = targetWindow.nodeWorkspace, workspace.arrangement == .tabbed {
        let source = workspace.tabbedGroup(containing: sourceWindow.windowId)
        return tabbedGroupDropDestination(resolution, source: source, sourceWindow: sourceWindow, targetWindow: targetWindow,
                                          subject: subject).map(intentOverlayDestination)
    }
    switch resolution.intent.zone {
        case .tab:
            if let destination = sameTabGroupReturnDestination(
                resolution: resolution,
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                detachOrigin: detachOrigin
            ) {
                return intentOverlayDestination(destination)
            }
            guard config.windowTabs.enabled,
                  isWindowDragIntentKindEnabled(.tabStack(targetWindowId: targetWindow.windowId)),
                  !shouldSuppressSameTabGroupTabDestination(
                      sourceWindow: sourceWindow,
                      targetWindow: targetWindow,
                      detachOrigin: detachOrigin
                  )
            else { return nil }
            return intentOverlayDestination(WindowDragIntentDestination(
                kind: .tabStack(targetWindowId: targetWindow.windowId),
                previewRect: windowDropIntentActivePreviewRect(for: resolution),
                interactionRect: resolution.targetFrame,
                title: "Insert Into Tabs",
                subtitle: "Drop in the top zone to add this window",
                previewStyle: .tabInsert,
                previewGeometry: .tabStrip,
                isGroup: false,
            ))
        case .middle:
            if let destination = sameTabGroupReturnDestination(
                resolution: resolution,
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                detachOrigin: detachOrigin
            ) {
                return intentOverlayDestination(destination)
            }
            guard let destination = swapDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                detachOrigin: detachOrigin,
            ) else { return nil }
            return intentOverlayDestination(destination)
        case .left, .right, .top, .bottom:
            guard let position = resolution.intent.zone.stackSplitPosition else { return nil }
            guard let destination = stackSplitDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                position: position,
                detachOrigin: detachOrigin,
            ) else { return nil }
            return intentOverlayDestination(destination)
    }
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

@MainActor
private func sameTabGroupReturnDestination(
    resolution: WindowDropIntentResolution,
    sourceWindow: Window,
    targetWindow: Window,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard subject == .window,
          detachOrigin == .tabStrip,
          config.windowTabs.enabled,
          let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .tabGroup,
          targetWindow.parent === sourceParent
    else { return nil }
    return WindowDragIntentDestination(
        kind: .reorderTab(windowId: sourceWindow.windowId, targetIndex: sourceWindow.ownIndex ?? 0),
        previewRect: windowDropIntentActivePreviewRect(for: resolution),
        interactionRect: resolution.targetFrame,
        title: "Return To Tabs",
        subtitle: "Drop to keep this tab in the current group",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
    )
}

func windowDropIntentActivePreviewRect(for resolution: WindowDropIntentResolution) -> Rect {
    resolution.zones.first { $0.zone == resolution.intent.zone }?.frame ?? resolution.targetFrame
}

@MainActor
func resolveWindowDropIntent(
    sourceWindow: Window,
    targetWindow: Window,
    targetNode: TreeNode,
    mouseLocation: CGPoint,
) -> WindowDropIntentResolution? {
    let targetFrame: Rect?
    if let tabGroup = targetNode as? TilingContainer, tabGroup.layout == .tabGroup {
        targetFrame = tabGroup.lastAppliedLayoutPhysicalRect
    } else {
        targetFrame = targetNode.windowDragVisibleRect
    }
    guard let targetFrame else { return nil }
    return WindowDropIntentResolver().resolve(
        sourceWindowId: sourceWindow.windowId,
        targetWindowId: targetWindow.windowId,
        pointer: mouseLocation,
        targetFrame: targetFrame,
    )
}
