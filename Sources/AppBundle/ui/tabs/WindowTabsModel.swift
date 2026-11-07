import AppKit

@MainActor
func updateWindowTabModel() async {
    defer { WindowBorderController.shared.refresh() }
    let didClearMouseInteractionChromeSuppression =
        WindowTabStripPanelController.shared.clearMouseInteractionChromeSuppressionIfInactive()
    // A Tabbed workspace needs its bar to switch windows even when tab strips are off.
    if let bars = await buildWorkspaceTabBarModels() { WorkspaceTabBarController.shared.update(bars) }
    guard TrayMenuModel.shared.isEnabled, config.windowTabs.enabled else {
        TrayMenuModel.shared.setIfChanged(\.windowTabStrips, [])
        WindowTabStripPanelController.shared.refresh(updateBorders: false)
        debugLog(.focus, "updateWindowTabModel disabled -> cleared")
        return
    }
    pruneCachedWindowTitles()

    let strips = await buildWindowTabStripViewModelsFromChromeItems()

    if TrayMenuModel.shared.windowTabStrips != strips {
        debugLog(.focus, "updateWindowTabModel apply strips old=\(TrayMenuModel.shared.windowTabStrips.map(\.frame)) new=\(strips.map(\.frame))")
        TrayMenuModel.shared.windowTabStrips = strips
        WindowTabStripPanelController.shared.refresh(updateBorders: false)
    } else {
        if didClearMouseInteractionChromeSuppression {
            WindowTabStripPanelController.shared.refresh(updateBorders: false)
        }
        debugLog(.focus, "updateWindowTabModel unchanged strips=\(strips.map(\.frame))")
    }
}
