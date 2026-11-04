import AppKit

private let windowTabGroupShellHorizontalInsetValue: CGFloat = 3
private let windowTabGroupShellTopInsetValue: CGFloat = 0
private let windowTabGroupShellBottomInsetValue: CGFloat = 3
private let windowTabBarMinimumHeightValue: CGFloat = 36

func windowTabGroupShellHorizontalInset() -> CGFloat {
    windowTabGroupShellHorizontalInsetValue
}

func windowTabGroupShellTopInset() -> CGFloat {
    windowTabGroupShellTopInsetValue
}

func windowTabGroupShellBottomInset() -> CGFloat {
    windowTabGroupShellBottomInsetValue
}

/// The height of the tab strip when it shows, over the top of the active window.
@MainActor
func resolvedWindowTabBarHeight() -> CGFloat {
    max(CGFloat(config.windowTabs.height), windowTabBarMinimumHeightValue)
}

/// With pills a tab group reserves no height: they sit in the gap, straddling the group's top
/// edge, and resting there opens the hover bar with the tabs. A tab strip takes its height.
@MainActor
func resolvedWindowTabReservedHeight() -> CGFloat {
    config.windowTabs.style == .tabs ? resolvedWindowTabBarHeight() : 0
}
