import AppKit

func shouldSuppressSwapDestination(sourceWindow: Window, subject: WindowDragSubject) -> Bool {
    subject == .window && sourceWindow.isFloating
}

/// A floating window dropped on another workspace stays floating there. True when it was one.
@MainActor
private func moveFloatingWindowIfNeeded(sourceNode: TreeNode, sourceWindow: Window, to targetWorkspace: Workspace) -> Bool {
    guard sourceNode is Window, sourceWindow.isFloating else { return false }
    sourceNode.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    return true
}

@MainActor
func applySidebarWorkspaceMove(sourceNode: TreeNode, sourceWindow: Window, targetWorkspace: Workspace) {
    if !moveFloatingWindowIfNeeded(sourceNode: sourceNode, sourceWindow: sourceWindow, to: targetWorkspace) {
        let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
        sourceNode.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
    }
}

// Internal to keep cross-workspace insertion semantics unit-testable.
@MainActor
func applyWorkspaceMove(sourceNode: TreeNode, sourceWindow: Window, mouseLocation: CGPoint, targetWorkspace: Workspace) {
    if moveFloatingWindowIfNeeded(sourceNode: sourceNode, sourceWindow: sourceWindow, to: targetWorkspace) {
        _ = sourceWindow.focusWindow()
        return
    }
    let swapTarget = mouseLocation.findIn(tree: targetWorkspace.rootTilingContainer, virtual: false)?.takeIf { $0.moveNode != sourceNode }
    let binding = workspaceMoveBindingData(
        targetWorkspace: targetWorkspace,
        swapTarget: swapTarget,
        mouseLocation: mouseLocation,
    )
    sourceNode.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
    _ = sourceWindow.focusWindow()
}

@MainActor
func applyWorkspaceZoneMove(
    sourceNode: TreeNode,
    sourceWindow: Window,
    targetWorkspace: Workspace,
    zone: WindowDropZone,
) {
    guard let position = zone.stackSplitPosition else {
        applyWorkspaceMove(
            sourceNode: sourceNode,
            sourceWindow: sourceWindow,
            mouseLocation: MousePointerTracker.shared.currentSample.point,
            targetWorkspace: targetWorkspace,
        )
        return
    }
    if moveFloatingWindowIfNeeded(sourceNode: sourceNode, sourceWindow: sourceWindow, to: targetWorkspace) {
        _ = sourceWindow.focusWindow()
        return
    }
    let targetRoot = workspaceSiblingInsertionRoot(
        targetWorkspace,
        orientation: position.orientation,
    )
    sourceNode.bind(
        to: targetRoot,
        adaptiveWeight: WEIGHT_AUTO,
        index: position.isPositive ? INDEX_BIND_LAST : 0,
    )
    _ = sourceWindow.focusWindow()
}
