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

/// A tab group reserves no height above its windows: its pills sit in the gap, straddling the
/// group's top edge, and resting on that edge opens the hover bar with the tabs.
@MainActor
func resolvedWindowTabReservedHeight() -> CGFloat { 0 }
