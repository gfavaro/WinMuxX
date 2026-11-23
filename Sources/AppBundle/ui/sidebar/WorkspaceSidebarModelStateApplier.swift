import AppKit

@MainActor
func clearWorkspaceSidebarModelState() {
    TrayMenuModel.shared.workspaceSidebarWorkspaces = []
    TrayMenuModel.shared.workspaceSidebarMonitorScopes = []
    TrayMenuModel.shared.workspaceSidebarProjects = []
    TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector = false
    WorkspaceSidebarPanel.refreshAll()
}

@MainActor
func applyWorkspaceSidebarModelState(_ state: WorkspaceSidebarModelState) {
    let changed = TrayMenuModel.shared.workspaceSidebarModelState != state
    TrayMenuModel.shared.workspaceSidebarModelState = state
    WorkspaceSidebarPanel.syncVisiblePanelModelsFromShared()
    if changed || WorkspaceSidebarPanel.visiblePanels.isEmpty {
        WorkspaceSidebarPanel.refreshAll()
    }
}

extension TrayMenuModel {
    /// The sidebar's shared state as one value. Each field is written only when it differs, so
    /// views observing one field are not redrawn by a change to another.
    var workspaceSidebarModelState: WorkspaceSidebarModelState {
        get {
            WorkspaceSidebarModelState(
                workspaces: workspaceSidebarWorkspaces,
                projects: workspaceSidebarProjects,
                activeProjectId: workspaceSidebarActiveProjectId,
                monitorScopes: workspaceSidebarMonitorScopes,
                focusedMonitorScopeId: workspaceSidebarFocusedMonitorScopeId,
                showsMonitorSelector: workspaceSidebarShowsMonitorSelector,
                topPadding: workspaceSidebarTopPadding,
            )
        }
        set {
            if workspaceSidebarWorkspaces != newValue.workspaces { workspaceSidebarWorkspaces = newValue.workspaces }
            if workspaceSidebarProjects != newValue.projects { workspaceSidebarProjects = newValue.projects }
            if workspaceSidebarActiveProjectId != newValue.activeProjectId { workspaceSidebarActiveProjectId = newValue.activeProjectId }
            if workspaceSidebarMonitorScopes != newValue.monitorScopes { workspaceSidebarMonitorScopes = newValue.monitorScopes }
            if workspaceSidebarFocusedMonitorScopeId != newValue.focusedMonitorScopeId { workspaceSidebarFocusedMonitorScopeId = newValue.focusedMonitorScopeId }
            if workspaceSidebarShowsMonitorSelector != newValue.showsMonitorSelector { workspaceSidebarShowsMonitorSelector = newValue.showsMonitorSelector }
            if workspaceSidebarTopPadding != newValue.topPadding { workspaceSidebarTopPadding = newValue.topPadding }
        }
    }
}
