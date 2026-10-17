import Common

/// Upgrade existing tiled roots without changing window membership or explicit tab groups.
/// Called at startup/import and when switching the configured default to dwindle, not on every refresh.
@MainActor
@discardableResult
func applyDwindleToExistingTiledWorkspaces() -> Bool {
    guard config.defaultRootContainerLayout == .dwindle else { return false }
    var changed = false
    for workspace in Workspace.all where config.workspaceLayouts[workspace.name]?.settings(on: workspace.workspaceMonitor).layout == nil {
        let root = workspace.rootTilingContainer
        if root.layout == .tiles {
            root.layout = .dwindle
            changed = true
        }
    }
    return changed
}
