import AppKit
import Common

struct WindowBorderCornerRadii: Equatable {
    let top: CGFloat
    let bottom: CGFloat
    var maximum: CGFloat { max(top, bottom) }
}

struct WindowBorderTarget: Equatable {
    let frame: CGRect
    let corners: WindowBorderCornerRadii
}

@MainActor
func windowBorderTarget(for window: Window, nativeFrame: CGRect) -> WindowBorderTarget? {
    let ordinary = WindowBorderTarget(frame: nativeFrame,
        corners: .init(top: systemWindowCornerRadius(), bottom: systemWindowCornerRadius()))
    // In a Tabbed workspace the tab bar belongs to the window shown under it: one border
    // encloses both, from the top of the bar to the bottom of the window.
    if let workspace = window.nodeWorkspace, workspace.arrangement == .tabbed, !workspace.presentsManagedFullscreen,
       let split = workspace.tabbedActiveUnit as? TilingContainer, split.allLeafWindowsRecursive.contains(where: { $0 === window }) {
        // A side-by-side tab has one border around the bar and all its windows, drawn by its front window.
        guard split.mostRecentWindowRecursive === window else { return nil }
        let area = workspaceTilingRect(workspace)
        return WindowBorderTarget(frame: CGRect(x: area.topLeftX, y: area.topLeftY, width: area.width, height: area.height),
            corners: .init(top: windowTabStripCornerRadius, bottom: systemWindowCornerRadius()))
    }
    if let workspace = window.nodeWorkspace, workspace.arrangement == .tabbed, !workspace.presentsManagedFullscreen,
       workspace.rootTilingContainer.mostRecentWindowRecursive === window {
        let top = workspaceTilingRect(workspace).topLeftY
        guard nativeFrame.maxY > top else { return ordinary }
        return WindowBorderTarget(frame: CGRect(x: nativeFrame.minX, y: top, width: nativeFrame.width, height: nativeFrame.maxY - top),
            corners: .init(top: windowTabStripCornerRadius, bottom: systemWindowCornerRadius()))
    }
    guard let group = window.nearestWindowTabGroup, group.usesWindowTabBehavior else { return ordinary }
    // Only the representative owns the group's outline, including during a tab switch
    // before the previously visible window has finished parking.
    guard group.tabActiveWindow === window else { return nil }
    let panels = WindowTabStripPanelController.shared
    guard group.showsWindowTabs, panels.mouseInteractionChromeMode != .hidden,
          !panels.hiddenPassiveTabGroupChromeIds.contains(ObjectIdentifier(group)) else { return ordinary }

    let groupRect: Rect
    if window.parent === group {
        // Invert the layout insets using live bounds, not a delayed strip snapshot.
        groupRect = windowTabGroupFrameRect(forActiveWindowContentRect: Rect(
            topLeftX: nativeFrame.minX, topLeftY: nativeFrame.minY,
            width: nativeFrame.width, height: nativeFrame.height))
    } else if let groupFrame = group.windowTabGroupFrameRect {
        // A tab may contain a split: the outer shell encloses every pane, not just
        // the representative leaf. Its layout frame is already the whole group.
        groupRect = groupFrame
    } else { return ordinary }
    let appRadius = windowTabGroupAppCornerRadius(activeWindowId: window.windowId)
    return WindowBorderTarget(frame: CGRect(origin: groupRect.topLeftCorner, size: groupRect.size),
        corners: .init(top: windowTabStripCornerRadius, bottom: appRadius + windowTabGroupShellBottomInset()))
}
