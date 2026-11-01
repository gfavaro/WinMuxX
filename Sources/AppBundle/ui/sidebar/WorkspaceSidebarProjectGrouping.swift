import Foundation

func workspaceSidebarVisibleWorkspacesByProject(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    selectedScopeId: String,
    focusedMonitorScopeId: String,
    browsedProjectId: WorkspaceProjectId? = nil,
) -> [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] {
    var result: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] = [:]
    for workspace in workspaces {
        if workspace.projectId != browsedProjectId &&
            !workspaceSidebarWorkspaceMatchesScope(
                workspace,
                selectedScopeId: selectedScopeId,
                focusedMonitorScopeId: focusedMonitorScopeId,
            )
        {
            continue
        }
        result[workspace.projectId, default: []].append(workspace)
    }
    return result
}

func workspaceSidebarWorkspaceIsOnOtherDisplay(
    _ workspace: WorkspaceSidebarWorkspaceViewModel,
    selectedScopeId: String,
) -> Bool {
    guard selectedScopeId != workspaceSidebarDefaultScopeId,
          selectedScopeId != workspaceSidebarFocusedScopeId
    else {
        return false
    }
    return workspace.monitorScopeId != selectedScopeId
}

/// Showing on another display right now, not merely owned by one. Most workspaces another display
/// owns are hidden; only the one it shows is marked, as WinMux marked workspaces in use there.
func workspaceSidebarWorkspaceIsShownOnOtherDisplay(
    _ workspace: WorkspaceSidebarWorkspaceViewModel,
    selectedScopeId: String,
) -> Bool {
    workspace.isVisible && workspaceSidebarWorkspaceIsOnOtherDisplay(workspace, selectedScopeId: selectedScopeId)
}
