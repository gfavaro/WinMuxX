import AppKit
import Common

@MainActor
func selectWorkspaceSidebarProject(
    _ projectId: WorkspaceProjectId,
    state: WorkspaceSidebarPanelState,
) {
    let knownProjects = workspaceProjects()
    let resolvedTargetScopeId = state.targetMonitorScopeId
    debugLog(.sidebarProject, "selectProjectBegin project=\(projectId.rawValue) known=\(knownProjects.map(\.id.rawValue)) targetScope=\(resolvedTargetScopeId) activeBefore=\(state.activeProjectId.rawValue)"
    )
    guard knownProjects.contains(where: { $0.id == projectId }) else {
        debugLog(.sidebarProject, "selectProjectAbort unknownProject=\(projectId.rawValue)")
        return
    }
    runWorkspaceSidebarSession {
        let monitor = workspaceSidebarTargetMonitor(
            scopeId: state.targetMonitorScopeId
        )
        debugLog(.sidebarProject, "selectProjectSession project=\(projectId.rawValue) monitor=\(monitor.monitorAppKitNsScreenScreensId) visibleBefore=\(monitor.activeWorkspace.name) activeProjectBefore=\(activeWorkspaceProjectId(for: monitor).rawValue)"
        )
        if let workspace = switchWorkspaceProject(projectId, on: monitor) {
            debugLog(.sidebarProject, "selectProjectSwitchResult project=\(projectId.rawValue) workspace=\(workspace.name) workspaceProject=\(workspace.projectId.rawValue)"
            )
            _ = workspace.focusWorkspace()
            state.activeProjectId = projectId
        } else {
            debugLog(.sidebarProject, "selectProjectSwitchResult project=\(projectId.rawValue) workspace=nil")
        }
        await updateWorkspaceSidebarModel()
        debugLog(.sidebarProject, "selectProjectEnd project=\(projectId.rawValue) activeAfter=\(state.activeProjectId.rawValue)"
        )
    }
}

@MainActor
func createWorkspaceSidebarProject(
    state: WorkspaceSidebarPanelState,
) {
    runWorkspaceSidebarSession {
        let project = createWorkspaceProject()
        let monitor = workspaceSidebarTargetMonitor(
            scopeId: state.targetMonitorScopeId
        )
        if let workspace = switchWorkspaceProject(project.id, on: monitor) {
            _ = workspace.focusWorkspace()
            state.activeProjectId = project.id
        }
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
func renameWorkspaceSidebarProject(_ projectId: WorkspaceProjectId, displayName: String) {
    runWorkspaceSidebarSession {
        try renameWorkspaceProject(projectId, displayName: displayName)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
func setWorkspaceSidebarProjectColor(_ project: WorkspaceSidebarProjectViewModel, colorHex: String?) {
    runWorkspaceSidebarSession {
        let normalizedColorHex = colorHex.flatMap(normalizedWorkspaceSidebarColorHex)
        if let normalizedColorHex {
            config.workspaceSidebar.projectColors[project.id.rawValue] = normalizedColorHex
        } else {
            config.workspaceSidebar.projectColors.removeValue(forKey: project.id.rawValue)
        }
        if !isUnitTest {
            try persistWorkspaceSidebarProjectColor(projectId: project.id.rawValue, colorHex: normalizedColorHex)
        }
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
func deleteWorkspaceSidebarProject(
    _ project: WorkspaceSidebarProjectViewModel,
    state: WorkspaceSidebarPanelState,
) {
    guard canDeleteWorkspaceProject(project.id) else { return }
    guard confirmWorkspaceSidebarProjectDeletion(project) else { return }
    runWorkspaceSidebarSession {
        try await deleteWorkspaceProjectFromSidebar(project.id)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
private func confirmWorkspaceSidebarProjectDeletion(_ project: WorkspaceSidebarProjectViewModel) -> Bool {
    let windowCount = windowsInWorkspaceProject(project.id).count
    guard windowCount > 0 else { return true }

    let alert = NSAlert()
    alert.messageText = "Close Project Windows?"
    alert.informativeText = """
    WinMux will ask macOS to close \(windowCount) window\(windowCount == 1 ? "" : "s") in “\(project.displayName)”. Apps may show their own confirmation dialogs for unsaved work. If any window stays open, WinMux will keep the project.
    """
    alert.addButton(withTitle: "Close Project")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning
    return alert.runModal() == .alertFirstButtonReturn
}
