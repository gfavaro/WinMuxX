/// UI projections and actions are kept separate from backend command and tree policy.
@MainActor
protocol WorkspaceBackendUI: AnyObject {
    var hasProjects: Bool { get }
    func sidebarWorkspaces(currentFocus: LiveFocus, labels: [String: String],
                           monitors: [Monitor]) async -> [WorkspaceSidebarWorkspaceViewModel]
    /// False leaves the action to the shared sidebar handler.
    func handleSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel, targetMonitorScopeId: String?) -> Bool
    func extraPaletteItems() -> [SwitcherPaletteItem]
    /// False leaves tray rendering to the shared code.
    func updateTray() -> Bool
}

@MainActor
final class VirtualWorkspaceBackendUI: WorkspaceBackendUI {
    var hasProjects: Bool { true }
    func sidebarWorkspaces(currentFocus: LiveFocus, labels: [String: String],
                           monitors: [Monitor]) async -> [WorkspaceSidebarWorkspaceViewModel] {
        await buildWorkspaceSidebarWorkspaceViewModels(currentFocus: currentFocus, workspaceLabels: labels, availableMonitors: monitors)
    }
    func handleSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel, targetMonitorScopeId: String?) -> Bool { false }
    func extraPaletteItems() -> [SwitcherPaletteItem] { [] }
    func updateTray() -> Bool { false }
}

@MainActor
final class NativeWorkspaceBackendUI: WorkspaceBackendUI {
    var hasProjects: Bool { false }
    func sidebarWorkspaces(currentFocus: LiveFocus, labels: [String: String],
                           monitors: [Monitor]) async -> [WorkspaceSidebarWorkspaceViewModel] {
        await buildNativeWorkspaceSidebarWorkspaceViewModels(currentFocus: currentFocus, workspaceLabels: labels, availableMonitors: monitors)
    }
    func handleSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel, targetMonitorScopeId: String?) -> Bool {
        handleNativeWorkspaceSidebarAction(action, viewModel: viewModel, targetMonitorScopeId: targetMonitorScopeId)
        return true
    }
    func extraPaletteItems() -> [SwitcherPaletteItem] { nativeListedPaletteItems() }
    func updateTray() -> Bool { updateNativeTrayText(); return true }
}
