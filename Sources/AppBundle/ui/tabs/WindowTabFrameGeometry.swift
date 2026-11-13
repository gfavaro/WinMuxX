import AppKit
import Common

@MainActor
func windowTabGroupFrameRect(forActiveWindowContentRect contentRect: Rect) -> Rect {
    let horizontalInset = windowTabGroupShellHorizontalInset()
    let topInset = resolvedWindowTabReservedHeight() + windowTabGroupShellTopInset()
    let bottomInset = windowTabGroupShellBottomInset()
    return Rect(
        topLeftX: contentRect.topLeftX - horizontalInset,
        topLeftY: contentRect.topLeftY - topInset,
        width: max(contentRect.width + horizontalInset * 2, 0),
        height: max(contentRect.height + topInset + bottomInset, 0),
    )
}

/// Where the window sits in a tab group's shell: under the header, inset on the sides and bottom
/// so its rounded corners sit inside the shell's instead of against its edge.
func windowTabGroupContentRect(inGroupFrame frame: Rect, headerHeight: CGFloat) -> Rect {
    let chrome = windowTabGroupChromeSize(headerHeight: headerHeight)
    return Rect(
        topLeftX: frame.topLeftX + windowTabGroupShellHorizontalInset(),
        topLeftY: frame.topLeftY + headerHeight + windowTabGroupShellTopInset(),
        width: max(frame.width - chrome.width, 0),
        height: max(frame.height - chrome.height, 0),
    )
}

/// The room a tab group's shell takes around its window: the header and the shell's insets.
func windowTabGroupChromeSize(headerHeight: CGFloat) -> CGSize {
    CGSize(width: windowTabGroupShellHorizontalInset() * 2,
           height: headerHeight + windowTabGroupShellTopInset() + windowTabGroupShellBottomInset())
}

@MainActor
func windowTabBarRect(forGroupFrameRect groupFrameRect: Rect) -> Rect {
    Rect(
        topLeftX: groupFrameRect.topLeftX,
        topLeftY: groupFrameRect.topLeftY,
        width: groupFrameRect.width,
        height: min(resolvedWindowTabBarHeight(), groupFrameRect.height),
    )
}

extension Rect {
    var toAppKitScreenRect: CGRect {
        CGRect(
            x: minX,
            y: mainMonitor.height - topLeftY - height,
            width: width,
            height: height,
        )
    }
}
