@MainActor
func automaticWorkspaceDisplayIndex(_ workspace: Workspace, focusedWorkspace: Workspace?) -> Int? {
    if workspace.isConfiguredPersistent { return parsePositiveWorkspaceDisplayIndex(workspace.name) }
    let persistent = projectHasPersistentWorkspaces(workspace.projectId)
    if !persistent, let index = workspace.restoredDisplayIndex { return index }
    let indices = automaticWorkspaceDisplayIndices(in: workspace.projectId, focusedWorkspace: focusedWorkspace)
    // A newly created transient slot may not enter retention until a window is
    // moved into it. Its provisional name still uses the next unreserved number.
    return indices[workspace.id] ?? (persistent ? lowestUnusedPositiveIndex(Set(indices.values)) : nil)
}

@MainActor
func projectHasPersistentWorkspaces(_ projectId: WorkspaceProjectId) -> Bool {
    projectWorkspaces(projectId: projectId).contains { !$0.isArchived && $0.isConfiguredPersistent }
}

/// Allocate live numbers once per project, using registry order rather than the
/// resulting display order. Presentation and labels must use the same allocation.
@MainActor
func automaticWorkspaceDisplayIndices(in projectId: WorkspaceProjectId, focusedWorkspace: Workspace? = nil) -> [WorkspaceId: Int] {
    let workspaces = projectWorkspaces(projectId: projectId).filter { !$0.isArchived }
    let visible = userFacingWorkspaces(workspaces, focusedWorkspace: focusedWorkspace)
    var indices: [WorkspaceId: Int] = [:]
    if workspaces.contains(where: \.isConfiguredPersistent) {
        var reserved = Set(workspaces.filter(\.isConfiguredPersistent).compactMap {
            parsePositiveWorkspaceDisplayIndex($0.name)
        })
        for workspace in workspaces where workspace.isConfiguredPersistent {
            indices[workspace.id] = parsePositiveWorkspaceDisplayIndex(workspace.name)
        }
        for workspace in visible where !workspace.isConfiguredPersistent {
            let index = lowestUnusedPositiveIndex(reserved)
            indices[workspace.id] = index
            reserved.insert(index)
        }
        return indices
    }
    for workspace in workspaces {
        if let index = workspace.isConfiguredPersistent
            ? parsePositiveWorkspaceDisplayIndex(workspace.name) : workspace.restoredDisplayIndex {
            indices[workspace.id] = index
        }
    }
    var reserved = Set(visible.filter { !$0.usesAutomaticDisplayName || $0.isConfiguredPersistent }
        .compactMap { parsePositiveWorkspaceDisplayIndex($0.name) })
    reserved.formUnion(visible.compactMap(\.restoredDisplayIndex))
    for candidate in visible where candidate.usesAutomaticDisplayName && !candidate.isConfiguredPersistent && candidate.restoredDisplayIndex == nil {
        let index = lowestUnusedPositiveIndex(reserved)
        indices[candidate.id] = index
        reserved.insert(index)
    }
    return indices
}

func automaticWorkspaceDisplayIndexFallback(_ workspaceName: String) -> Int? {
    sidebarDraftWorkspaceIndex(workspaceName) ?? automaticWorkspaceIndex(workspaceName)
}

@MainActor
func scopedAutomaticDisplayWorkspaces(current: Workspace) -> [Workspace] {
    orderedWorkspacesForPresentation()
        .filter { $0.projectId == current.projectId }
        .filter { userFacingWorkspaces([$0], focusedWorkspace: current).contains($0) }
        .filter { $0.usesAutomaticDisplayName || $0.isConfiguredPersistent || projectHasPersistentWorkspaces(current.projectId) }
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
        $0.usesAutomaticDisplayName || projectHasPersistentWorkspaces(current.projectId)
            ? automaticWorkspaceDisplayIndex($0, focusedWorkspace: current)
            : parsePositiveWorkspaceDisplayIndex($0.name)
    }
    if projectHasPersistentWorkspaces(current.projectId) {
        return lowestUnusedPositiveIndex(Set(indices))
    }
    return (indices.max() ?? 0) + 1
}
