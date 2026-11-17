import AppKit

@MainActor
func tabStackDestination(targetWindow: Window, mouseLocation: CGPoint? = nil) -> WindowDragIntentDestination? {
    guard isWindowDragIntentKindEnabled(.tabStack(targetWindowId: targetWindow.windowId)),
          let rects = targetWindow.tabStackTargetRects,
          mouseLocation.map(rects.interactionRect.contains) ?? true
    else { return nil }
    return WindowDragIntentDestination(
        kind: .tabStack(targetWindowId: targetWindow.windowId),
        previewRect: rects.previewRect,
        interactionRect: rects.interactionRect,
        title: "Insert Into Tabs",
        subtitle: "Drop near the top edge to add this window",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
    )
}

/// A tab dragged out of its own tab group and dropped back on that group. Over the group's tab
/// strip it goes where the pointer is among the tabs; anywhere else on the group (`resolution`, a
/// drop zone of its window) it goes back where it was. One rule for both, so the hint and the
/// result always agree.
@MainActor
func ownTabGroupReturnDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    resolution: WindowDropIntentResolution? = nil,
) -> WindowDragIntentDestination? {
    guard subject == .window,
          detachOrigin == .tabStrip,
          config.windowTabs.enabled,
          let sourceParent = sourceWindow.sharedTabGroup(with: targetWindow)
    else { return nil }
    let sourceIndex = sourceWindow.ownIndex ?? 0
    if let targetFrame = sourceParent.windowDragVisibleRect,
       let stripRect = sourceParent.windowTabDropZoneRect,
       let stripInteraction = sourceParent.windowTabDropInteractionRect,
       stripInteraction.contains(mouseLocation) {
        let targetIndex = tabReentryTargetIndex(mouseLocation: mouseLocation, tabStripRect: stripRect,
                                                tabCount: sourceParent.children.count, sourceIndex: sourceIndex)
        return ownTabGroupReturn(sourceWindow, targetIndex: targetIndex, previewRect: stripRect,
            interactionRect: stripInteraction,
            overlay: WindowDropIntentOverlayModel(targetFrame: targetFrame, activeZone: .tab, cornerRadius: nil))
    }
    guard let resolution else { return nil }
    return ownTabGroupReturn(sourceWindow, targetIndex: sourceIndex,
        previewRect: windowDropIntentActivePreviewRect(for: resolution), interactionRect: resolution.targetFrame, overlay: nil)
}

private func ownTabGroupReturn(_ sourceWindow: Window, targetIndex: Int, previewRect: Rect, interactionRect: Rect,
                               overlay: WindowDropIntentOverlayModel?) -> WindowDragIntentDestination {
    WindowDragIntentDestination(
        kind: .reorderTab(windowId: sourceWindow.windowId, targetIndex: targetIndex),
        previewRect: previewRect,
        interactionRect: interactionRect,
        title: "Return To Tabs",
        subtitle: "Drop to put this tab back in its group",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
        dropIntentOverlay: overlay,
    )
}

func tabReentryTargetIndex(
    mouseLocation: CGPoint,
    tabStripRect: Rect,
    tabCount: Int,
    sourceIndex: Int? = nil,
    minimumTabWidth: CGFloat = windowTabStripMinimumTabWidth,
) -> Int {
    guard tabCount > 1, tabStripRect.width > 0 else { return 0 }
    let insertionSlot = tabInsertionSlot(mouseLocation: mouseLocation, tabStripRect: tabStripRect, tabCount: tabCount,
                                         minimumTabWidth: minimumTabWidth)
    guard let sourceIndex else {
        return max(0, min(insertionSlot, tabCount - 1))
    }
    let adjustedTarget = insertionSlot > sourceIndex ? insertionSlot - 1 : insertionSlot
    return max(0, min(adjustedTarget, tabCount - 1))
}

/// The gap between tabs, from 0 before the first to `tabCount` after the last, nearest the pointer.
func tabInsertionSlot(
    mouseLocation: CGPoint,
    tabStripRect: Rect,
    tabCount: Int,
    minimumTabWidth: CGFloat = windowTabStripMinimumTabWidth,
) -> Int {
    guard tabCount > 0, tabStripRect.width > 0 else { return 0 }
    let tabWidth = windowTabStripTabWidth(stripWidth: tabStripRect.width, count: tabCount, minimum: minimumTabWidth)
    let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
    let firstTabMinX = tabStripRect.minX + windowTabStripContentHorizontalPadding
    let localX = mouseLocation.x - firstTabMinX
    let hoveredTabIndex = max(0, min(Int(floor(localX / effectiveTabWidth)), tabCount - 1))
    let hoveredTabCenterX = firstTabMinX + CGFloat(hoveredTabIndex) * effectiveTabWidth + tabWidth / 2
    return hoveredTabIndex + (mouseLocation.x >= hoveredTabCenterX ? 1 : 0)
}

func tabReentrySourceVisualOffset(
    mouseLocation: CGPoint,
    tabStripRect: Rect,
    tabCount: Int,
    sourceIndex: Int,
    minimumTabWidth: CGFloat = windowTabStripMinimumTabWidth,
) -> CGFloat {
    guard tabCount > 1, tabStripRect.width > 0 else { return 0 }
    let tabWidth = windowTabStripTabWidth(stripWidth: tabStripRect.width, count: tabCount, minimum: minimumTabWidth)
    let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
    let sourceCenterX = tabStripRect.minX
        + windowTabStripContentHorizontalPadding
        + CGFloat(sourceIndex) * effectiveTabWidth
        + tabWidth / 2
    let minOffset = -CGFloat(sourceIndex) * effectiveTabWidth
    let maxOffset = CGFloat(max(tabCount - 1 - sourceIndex, 0)) * effectiveTabWidth
    return max(min(mouseLocation.x - sourceCenterX, maxOffset), minOffset)
}
