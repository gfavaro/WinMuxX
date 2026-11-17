import AppKit

/// The drag stages shared by the arrangements that drop through the tree: Dwindle, Master and
/// Scrolling. A drop lands on a window of the tree, and the tree's own containers decide where.
@MainActor
final class TreeWindowDragArrangement: WindowDragArrangement {
    static let shared = TreeWindowDragArrangement()
    private init() {}

    func surfaceDestination(
        sourceWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination? {
        if let selfTabDestination = selfTabGroupSurfaceDestination(
            sourceWindow: sourceWindow,
            mouseLocation: mouseLocation,
            subject: subject,
            detachOrigin: detachOrigin,
        ) {
            return selfTabDestination
        }

        let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
        let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
        if shouldSuppressSelfGroupSurfaceTarget(
            sourceNode: sourceNode,
            targetWorkspace: targetWorkspace,
            mouseLocation: mouseLocation,
            subject: subject,
            sourceWindow: sourceWindow,
        ) {
            return nil
        }
        guard let targetWindow = mouseLocation.findWindowDragTarget(in: targetWorkspace.rootTilingContainer, excluding: sourceNode) else {
            logWindowDragHitTestIfNeeded(
                signature: "surface:none:source=\(sourceWindow.windowId):subject=\(debugDescribe(subject))",
                "windowDragTarget.none source=\(debugDescribe(sourceWindow)) subject=\(debugDescribe(subject)) mouse=\(debugDescribe(mouseLocation)) workspace=\(targetWorkspace.name)"
            )
            return nil
        }
        logWindowDragHitTestIfNeeded(
            signature: "surface:target=\(targetWindow.windowId):source=\(sourceWindow.windowId):subject=\(debugDescribe(subject))",
            "windowDragTarget.surface source=\(debugDescribe(sourceWindow)) subject=\(debugDescribe(subject)) mouse=\(debugDescribe(mouseLocation)) target=\(debugDescribe(targetWindow))"
        )
        return windowSurfaceDestination(
            sourceWindow: sourceWindow,
            targetWindow: targetWindow,
            mouseLocation: mouseLocation,
            subject: subject,
            detachOrigin: detachOrigin,
        )
    }

    func windowDestination(
        sourceWindow: Window,
        targetWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination? {
        let targetNode = dragIntentTargetNode(
            sourceWindow: sourceWindow,
            targetWindow: targetWindow,
            subject: subject,
            detachOrigin: detachOrigin,
        )
        if let reentryDestination = ownTabGroupReturnDestination(
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
        if detachOrigin == .tabStrip, subject == .window, sourceWindow.sharedTabGroup(with: targetWindow) != nil {
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

    func dropIntentDestination(
        resolution: WindowDropIntentResolution,
        sourceWindow: Window,
        targetWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination? {
        switch resolution.intent.zone {
            case .tab:
                if let destination = ownTabGroupReturnDestination(
                    sourceWindow: sourceWindow,
                    targetWindow: targetWindow,
                    mouseLocation: mouseLocation,
                    subject: subject,
                    detachOrigin: detachOrigin,
                    resolution: resolution,
                ) {
                    return destination
                }
                guard config.windowTabs.enabled,
                      isWindowDragIntentKindEnabled(.tabStack(targetWindowId: targetWindow.windowId)),
                      !shouldSuppressSameTabGroupTabDestination(
                          sourceWindow: sourceWindow,
                          targetWindow: targetWindow,
                          detachOrigin: detachOrigin
                      )
                else { return nil }
                return WindowDragIntentDestination(
                    kind: .tabStack(targetWindowId: targetWindow.windowId),
                    previewRect: windowDropIntentActivePreviewRect(for: resolution),
                    interactionRect: resolution.targetFrame,
                    title: "Insert Into Tabs",
                    subtitle: "Drop in the top zone to add this window",
                    previewStyle: .tabInsert,
                    previewGeometry: .tabStrip,
                    isGroup: false,
                )
            case .middle:
                if let destination = ownTabGroupReturnDestination(
                    sourceWindow: sourceWindow,
                    targetWindow: targetWindow,
                    mouseLocation: mouseLocation,
                    subject: subject,
                    detachOrigin: detachOrigin,
                    resolution: resolution,
                ) {
                    return destination
                }
                return swapDestination(
                    sourceWindow: sourceWindow,
                    targetWindow: targetWindow,
                    subject: subject,
                    detachOrigin: detachOrigin,
                )
            case .left, .right, .top, .bottom:
                guard let position = resolution.intent.zone.stackSplitPosition else { return nil }
                return stackSplitDestination(
                    sourceWindow: sourceWindow,
                    targetWindow: targetWindow,
                    subject: subject,
                    position: position,
                    detachOrigin: detachOrigin,
                )
        }
    }

    func updateBarDropPreview(sourceWindowId: UInt32, destination: WindowDragIntentDestination) -> Bool {
        // The tree has no bar of its own: a tab going back into one of its tab groups is shown
        // by the shared reentry preview.
        false
    }

    func applyDrop(kind: WindowDragIntentKind, sourceWindow: Window, subject: WindowDragSubject) -> Bool? {
        // In a Scrolling workspace the strip then shows the column the window landed in, whole.
        defer {
            if let workspace = sourceWindow.nodeWorkspace, workspace.arrangement == .scrolling {
                workspace.scrollingState.lastFocusWindowId = nil
            }
        }
        let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
        // A Tabbed workspace's handle carries its whole group, which the tree does not hold.
        let carriedGroup = subject == .group ? tabbedGroupCarried(by: sourceWindow) : nil
        defer { if let carriedGroup { bringTabbedGroupAlong(carriedGroup, after: sourceWindow) } }
        // Every drop that changes the layout first records it, and the windows it moves ignore the
        // move events their own relayout causes.
        guard let moved = windowIdsMovedByDrop(kind, sourceWindowId: sourceWindow.windowId) else { return false }
        syncClosedWindowsCacheToCurrentWorld()
        suppressPostDragAxObserverEvents(for: moved)
        switch kind {
            case .insertTab:
                return false
            case .reorderTab(let windowId, let targetIndex):
                guard subject == .window,
                      sourceWindow.windowId == windowId
                else { return false }
                // A tab dragged out of a Tabbed workspace's bar and back moves along that bar.
                if let workspace = sourceWindow.nodeWorkspace, workspace.arrangement == .tabbed,
                   let group = workspace.tabbedGroup(containing: windowId) {
                    guard workspace.insertTabbedTab(windowId, intoBarOf: group.barGroup, at: targetIndex) else { return false }
                    return sourceWindow.focusWindow()
                }
                return reorderWindowTabInCurrentGroup(sourceWindow, toIndex: targetIndex)
            case .tabStack(let targetWindowId):
                guard subject == .window else { return false }
                guard let targetWindow = Window.get(byId: targetWindowId),
                      sourceWindow != targetWindow
                else { return false }
                createOrAppendWindowTabStack(sourceWindow: sourceWindow, onto: targetWindow)
                return true
            case .detachTab(let windowId):
                guard sourceWindow.windowId == windowId else { return false }
                return removeWindowFromTabStack(sourceWindow)
            case .stackSplit(let targetWindowId, let position):
                guard let targetWindow = Window.get(byId: targetWindowId)
                else { return false }
                return applyWindowStackSplitDragIntent(
                    sourceWindow: sourceWindow,
                    sourceSubject: subject,
                    targetWindow: targetWindow,
                    position: position,
                )
            case .swap(let targetWindowId):
                guard let targetWindow = Window.get(byId: targetWindowId)
                else { return false }
                return applyWindowSwapDragIntent(
                    sourceWindow: sourceWindow,
                    sourceSubject: subject,
                    targetWindow: targetWindow,
                )
            case .moveToWorkspace(let workspaceName):
                guard let targetWorkspace = Workspace.existing(byName: workspaceName) else { return false }
                if pendingWindowDragIntent?.previewStyle == .sidebarWorkspaceMove {
                    applySidebarWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, targetWorkspace: targetWorkspace)
                } else {
                    applyWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, mouseLocation: mouseLocation, targetWorkspace: targetWorkspace)
                }
                return true
            case .moveToWorkspaceZone(let workspaceName, let zone):
                guard let targetWorkspace = Workspace.existing(byName: workspaceName) else { return false }
                applyWorkspaceZoneMove(sourceNode: sourceNode, sourceWindow: sourceWindow, targetWorkspace: targetWorkspace, zone: zone)
                return true
            case .createWorkspace(let projectId, let monitorScopeId):
                return createWorkspaceFromSidebarDrag(
                    sourceNode: sourceNode,
                    sourceWindow: sourceWindow,
                    projectId: projectId,
                    monitorScopeId: monitorScopeId,
                )
            case .sidebarHover, .unavailable:
                return false
        }
    }
}

@MainActor
private func selfTabGroupSurfaceDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard subject == .window,
          detachOrigin == .tabStrip,
          let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .tabGroup,
          sourceParent.lastAppliedLayoutPhysicalRect?.contains(mouseLocation) == true
    else { return nil }
    let targetWindow =
        sourceParent.tabActiveWindow?.takeIf { $0 != sourceWindow } ??
        sourceParent.children.compactMap { $0 as? Window }.first { $0 != sourceWindow } ??
        sourceParent.mostRecentWindowRecursive?.takeIf { $0 != sourceWindow } ??
        sourceParent.anyLeafWindowRecursive?.takeIf { $0 != sourceWindow } ??
        sourceWindow
    logWindowDragHitTestIfNeeded(
        signature: "surface:self-tab-group-direct:source=\(sourceWindow.windowId)",
        "windowDragTarget.selfTabGroupDirect source=\(debugDescribe(sourceWindow)) mouse=\(debugDescribe(mouseLocation)) target=\(debugDescribe(targetWindow)) container=\(debugDescribe(sourceParent))"
    )
    return windowSurfaceDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    )
}

@MainActor
private func shouldSuppressSelfGroupSurfaceTarget(
    sourceNode: TreeNode,
    targetWorkspace: Workspace,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    sourceWindow: Window,
) -> Bool {
    guard subject == .group,
          let sourceWorkspace = sourceNode.nodeWorkspace,
          sourceWorkspace === targetWorkspace,
          sourceNode.windowDragVisibleRect?.contains(mouseLocation) == true
    else { return false }
    logWindowDragHitTestIfNeeded(
        signature: "surface:self-group:source=\(sourceWindow.windowId)",
        "windowDragTarget.selfGroup source=\(debugDescribe(sourceWindow)) mouse=\(debugDescribe(mouseLocation)) sourceNode=\(debugDescribe(sourceNode))"
    )
    return true
}
