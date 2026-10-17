import Common

@MainActor
func dragStackLayout(for targetWindow: Window, defaultLayout: Layout? = nil) -> Layout {
    if let parent = targetWindow.parent as? TilingContainer,
       parent.layout == .tabGroup || parent.layout == .stacked {
        return parent.layout
    }
    return defaultLayout ?? config.dragStackLayout
}

@MainActor
func createOrAppendWindowTabStack(sourceWindow: Window, onto targetWindow: Window, newGroupLayout: Layout = .tabGroup) {
    guard sourceWindow != targetWindow else { return }
    let layout = dragStackLayout(for: targetWindow, defaultLayout: newGroupLayout)
    let targetRect = layout == .tabGroup
        ? normalizeTabStackSourceWindowFrame(sourceWindow: sourceWindow, targetWindow: targetWindow) : nil
    if let targetParent = targetWindow.parent as? TilingContainer,
       targetParent.layout == .tabGroup || targetParent.layout == .stacked
    {
        appendWindowToExistingStack(
            sourceWindow: sourceWindow,
            targetWindow: targetWindow,
            targetParent: targetParent,
            targetRect: targetRect,
        )
        return
    }

    let targetBinding = targetWindow.unbindFromParent()
    let newOrientation = (targetBinding.parent as? TilingContainer)?.orientation.opposite ?? .h
    let newParent = TilingContainer(
        parent: targetBinding.parent,
        adaptiveWeight: targetBinding.adaptiveWeight,
        newOrientation,
        layout,
        index: targetBinding.index,
    )
    sourceWindow.unbindFromParent()
    targetWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
    sourceWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    if let targetRect {
        synchronizeTabbedWindowCache(targetWindow, rect: targetRect)
        synchronizeTabGroupCachedFrames(newParent, rect: targetRect)
    }
    sourceWindow.markAsMostRecentChild()
    _ = sourceWindow.focusWindow()
}

@MainActor
func reorderWindowTabInCurrentGroup(_ sourceWindow: Window, toIndex targetIndex: Int) -> Bool {
    guard let parent = sourceWindow.parent as? TilingContainer,
          parent.layout == .tabGroup,
          let currentIndex = sourceWindow.ownIndex
    else { return false }
    let clampedTarget = max(0, min(targetIndex, parent.children.count - 1))
    guard clampedTarget != currentIndex else { return true }
    let binding = sourceWindow.unbindFromParent()
    sourceWindow.bind(to: parent, adaptiveWeight: binding.adaptiveWeight, index: clampedTarget)
    sourceWindow.markAsMostRecentChild()
    _ = sourceWindow.focusWindow()
    return true
}

@MainActor
private func appendWindowToExistingStack(
    sourceWindow: Window,
    targetWindow: Window,
    targetParent: TilingContainer,
    targetRect: Rect?,
) {
    if let targetRect {
        synchronizeTabbedWindowCache(targetWindow, rect: targetRect)
        synchronizeTabGroupCachedFrames(targetParent, rect: targetRect, excluding: sourceWindow.windowId)
    }
    let targetIndex = targetWindow.ownIndex.orDie()
    let sourceIndex = sourceWindow.ownIndex
    let sourceWasInTargetParent = sourceWindow.parent === targetParent
    sourceWindow.unbindFromParent()
    let insertIndex = if sourceWasInTargetParent, let sourceIndex {
        sourceIndex < targetIndex ? targetIndex : targetIndex + 1
    } else {
        targetIndex + 1
    }
    sourceWindow.bind(to: targetParent, adaptiveWeight: WEIGHT_AUTO, index: insertIndex)
    sourceWindow.markAsMostRecentChild()
    _ = sourceWindow.focusWindow()
}
