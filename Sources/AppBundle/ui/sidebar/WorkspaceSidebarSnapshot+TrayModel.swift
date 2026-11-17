import Foundation

/// One display's sidebar: the shared workspaces and projects, as that display's panel shows them.
@MainActor
func workspaceSidebarSnapshot(shared: TrayMenuModel, panel: WorkspaceSidebarPanelState) -> WorkspaceSidebarSnapshot {
    let visibleWorkspaceNames = visibleWorkspaceNamesForSidebar(
        workspaces: shared.workspaceSidebarWorkspaces,
        selectedMonitorScopeId: panel.selectedMonitorScopeId,
        focusedMonitorScopeId: shared.workspaceSidebarFocusedMonitorScopeId,
    )
    return WorkspaceSidebarSnapshot(
        workspaces: shared.workspaceSidebarWorkspaces,
        projects: shared.workspaceSidebarProjects,
        activeProjectId: panel.activeProjectId,
        monitorScopes: shared.workspaceSidebarMonitorScopes,
        selectedMonitorScopeId: panel.selectedMonitorScopeId,
        targetMonitorScopeId: panel.targetMonitorScopeId,
        focusedMonitorScopeId: shared.workspaceSidebarFocusedMonitorScopeId,
        visibleWidth: panel.visibleWidth,
        // Hover is shared; a panel shows it only on a workspace it lists.
        hoveredWorkspaceName: sanitizedWorkspaceSidebarHoveredWorkspaceName(
            visibleWorkspaceNames: visibleWorkspaceNames,
            hoveredWorkspaceName: shared.workspaceSidebarHoveredWorkspaceName,
        ),
        dropPreview: shared.workspaceSidebarDropPreview,
        configuration: panel.configuration,
    )
}
