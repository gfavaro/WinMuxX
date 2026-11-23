import AppKit

@MainActor
func updateWorkspaceSidebarModel() async {
    guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled else {
        clearWorkspaceSidebarModelState()
        return
    }

    pruneCachedWindowTitles()
    let state = await buildWorkspaceSidebarModelState()
    applyWorkspaceSidebarModelState(state)
}
