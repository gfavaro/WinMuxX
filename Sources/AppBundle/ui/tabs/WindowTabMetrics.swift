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

/// A tab group reserves its tab bar's height above its windows.
@MainActor
func resolvedWindowTabReservedHeight() -> CGFloat { resolvedWindowTabBarHeight() }
