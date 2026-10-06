@MainActor
func automaticWorkspaceDisplayIndex(_ workspace: Workspace, focusedWorkspace: Workspace?) -> Int? {
    if workspace.isConfiguredPersistent { return parsePositiveWorkspaceDisplayIndex(workspace.name) }
    if let index = workspace.restoredDisplayIndex { return index }
    let visible = userFacingWorkspaces(
        projectWorkspaces(projectId: workspace.projectId).filter { !$0.isArchived },
        focusedWorkspace: focusedWorkspace
    )
    var reserved = Set(visible.filter { !$0.usesAutomaticDisplayName || $0.isConfiguredPersistent }
        .compactMap { parsePositiveWorkspaceDisplayIndex($0.name) })
    reserved.formUnion(visible.compactMap(\.restoredDisplayIndex))
    for candidate in visible where candidate.usesAutomaticDisplayName && !candidate.isConfiguredPersistent && candidate.restoredDisplayIndex == nil {
        let index = lowestUnusedPositiveIndex(reserved)
        if candidate === workspace { return index }
        reserved.insert(index)
    }
    return nil
}

func automaticWorkspaceDisplayIndexFallback(_ workspaceName: String) -> Int? {
    sidebarDraftWorkspaceIndex(workspaceName) ?? automaticWorkspaceIndex(workspaceName)
}

@MainActor
func scopedAutomaticDisplayWorkspaces(current: Workspace) -> [Workspace] {
    orderedWorkspacesForPresentation()
        .filter { $0.projectId == current.projectId }
        .filter { userFacingWorkspaces([$0], focusedWorkspace: current).contains($0) }
        .filter(\.usesAutomaticDisplayName)
}

@MainActor
func createAdjacentTransientBlankWorkspaceIfAllowed(named workspaceName: String, from current: Workspace) -> Workspace? {
    guard let targetIndex = parsePositiveWorkspaceDisplayIndex(workspaceName) else {
        return nil
    }
    let automaticDisplayWorkspaces = scopedAutomaticDisplayWorkspaces(current: current)
    guard targetIndex == nextAdjacentWorkspaceDisplayIndex(current: current) else { return nil }
    if let lastWorkspace = automaticDisplayWorkspaces.last,
       orderedUserFacingWorkspaces(in: current.projectId, focusedWorkspace: current).count > 1,
       lastWorkspace.isOrdinaryEmptySlot {
        return nil
    }

    let workspace = Workspace.get(byName: nextSidebarCreatedWorkspaceName(projectId: current.projectId, monitor: current.workspaceMonitor))
    workspace.markAsTransientBlank()
    workspace.assignProject(current.projectId)
    workspace.seedMonitorIfNeeded(current.workspaceMonitor)
    return workspace
}

@MainActor
func nextAdjacentWorkspaceDisplayIndex(current: Workspace) -> Int {
    let indices = orderedUserFacingWorkspaces(in: current.projectId, focusedWorkspace: current).compactMap {
        $0.usesAutomaticDisplayName
            ? automaticWorkspaceDisplayIndex($0, focusedWorkspace: current)
            : parsePositiveWorkspaceDisplayIndex($0.name)
    }
    return (indices.max() ?? 0) + 1
}
