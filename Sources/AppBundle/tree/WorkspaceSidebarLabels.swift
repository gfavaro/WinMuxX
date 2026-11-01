import Common

@MainActor
func nextSidebarDraftWorkspaceName() -> String {
    clearOrphanedWorkspaceSidebarLabels()
    let nextIndex = lowestUnusedPositiveIndex(Set(runtime.workspaces.workspaceIdByName.keys.compactMap(sidebarDraftWorkspaceIndex)))
    return "\(sidebarDraftWorkspacePrefix)\(nextIndex)"
}

@MainActor
func nextSidebarCreatedWorkspaceName(projectId: WorkspaceProjectId = workspaceProjectDefaultId, monitor: Monitor = mainMonitor) -> String {
    nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor)
}

func isSidebarDraftWorkspaceName(_ name: String) -> Bool {
    name.hasPrefix(sidebarDraftWorkspacePrefix)
}

func sidebarDraftWorkspaceIndex(_ name: String) -> Int? {
    guard isSidebarDraftWorkspaceName(name) else { return nil }
    let suffix = name.replacingOccurrences(of: sidebarDraftWorkspacePrefix, with: "")
    return Int(suffix)
}

@MainActor
func clearWorkspaceSidebarLabelIfNeeded(_ workspaceName: String) {
    guard config.workspaceSidebar.workspaceLabels.removeValue(forKey: workspaceName) != nil else { return }
    if !isUnitTest {
        try? persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: nil)
    }
}

/// Only internal sidebar draft names are recycled, so only their stale labels go. A label
/// the user wrote for a workspace that does not exist yet (one a rule or a window will
/// create) stays in the config (WinMux issue #27).
@MainActor
func clearOrphanedWorkspaceSidebarLabels() {
    for workspaceName in config.workspaceSidebar.workspaceLabels.keys
    where isSidebarDraftWorkspaceName(workspaceName) && runtime.workspaces.workspace(named: workspaceName) == nil
    {
        clearWorkspaceSidebarLabelIfNeeded(workspaceName)
    }
}

@MainActor
func workspacePresentationDisplayIndex(_ workspace: Workspace, focusedWorkspace: Workspace? = nil) -> Int? {
    if projectHasPersistentWorkspaces(workspace.projectId) {
        return automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: focusedWorkspace ?? focus.workspace)
    }
    return orderedUserFacingWorkspaces(in: workspace.projectId, focusedWorkspace: focusedWorkspace ?? focus.workspace)
        .firstIndex(of: workspace).map { $0 + 1 }
}

@MainActor
func workspaceDefaultDisplayName(_ workspaceName: String) -> String {
    if let workspace = Workspace.existing(byName: workspaceName) {
        if workspace.isConfiguredPersistent {
            return parsePositiveWorkspaceDisplayIndex(workspaceName).map { "Workspace \($0)" } ?? workspaceName
        }
        if let index = workspacePresentationDisplayIndex(workspace)
        {
            return "Workspace \(index)"
        }
        // A slot not yet presented (for example, a newly created empty slot)
        // can still use its provisional index until it enters the visible list.
        let provisional = orderedWorkspaces(in: workspace.projectId).filter {
            $0 === workspace || isUserFacingWorkspace($0, focusedWorkspace: focus.workspace)
        }
        if let index = provisional.firstIndex(of: workspace) {
            return "Workspace \(index + 1)"
        }
        return workspaceName
    }
    if let index = sidebarDraftWorkspaceIndex(workspaceName) {
        return "Workspace \(index)"
    }
    return workspaceName
}

@MainActor
func workspaceDisplayName(_ workspaceName: String) -> String {
    if let configuredName = config.workspaceSidebar.workspaceLabels[workspaceName]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !configuredName.isEmpty
    {
        return configuredName
    }
    return workspaceDefaultDisplayName(workspaceName)
}
