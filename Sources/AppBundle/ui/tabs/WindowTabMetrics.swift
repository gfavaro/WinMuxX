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

/// The height a tab group reserves above its windows: a thin rail of pills, one per tab.
/// The full strip opens over the window only while the rail is hovered.
let windowTabPillRailHeight: CGFloat = 12

@MainActor
func resolvedWindowTabReservedHeight() -> CGFloat {
    min(windowTabPillRailHeight, resolvedWindowTabBarHeight())
}
