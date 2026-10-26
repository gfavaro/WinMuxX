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
    guard !window.isConcealedByScrolling || window.nodeWorkspace?.arrangement != .scrolling else { return nil }
    let ordinary = WindowBorderTarget(frame: nativeFrame,
        corners: .init(top: systemWindowCornerRadius(), bottom: systemWindowCornerRadius()))
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
