import AppKit

/// Everything the sidebars show that comes from the workspaces and displays, as one comparable value.
struct WorkspaceSidebarModelState: Equatable {
    let workspaces: [WorkspaceSidebarWorkspaceViewModel]
    let projects: [WorkspaceSidebarProjectViewModel]
    let activeProjectId: WorkspaceProjectId
    let monitorScopes: [WorkspaceSidebarMonitorScopeViewModel]
    let focusedMonitorScopeId: String
    let showsMonitorSelector: Bool
    let topPadding: CGFloat
}
