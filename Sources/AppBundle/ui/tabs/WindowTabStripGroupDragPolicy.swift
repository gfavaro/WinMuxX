@MainActor
func shouldPromoteTabStripDragToGroup(windowId: UInt32) -> Bool {
    if shouldContinueCurrentGroupDrag(windowId: windowId) {
        return true
    }
    guard let window = Window.get(byId: windowId) else { return false }
    let isOptionPressed = currentSessionModifierFlags().contains(.maskAlternate)
    return shouldPromoteWindowDragToTabGroupDrag(
        isOptionPressed: isOptionPressed,
        isTabbedWindow: isWindowInDraggableTabGroup(window),
    )
}

@MainActor
func shouldAllowTabStripChromeGroupDrag(windowId: UInt32) -> Bool {
    if shouldContinueCurrentGroupDrag(windowId: windowId) {
        return true
    }
    guard let window = Window.get(byId: windowId) else { return false }
    // A Tabbed workspace's handle carries its whole tab group.
    return isWindowInDraggableTabGroup(window) || window.nodeWorkspace?.arrangement == .tabbed && window.parent is TilingContainer
}
