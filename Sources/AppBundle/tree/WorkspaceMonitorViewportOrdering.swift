import AppKit

@MainActor func getOrCreateMonitorViewportFallbackWorkspace(for monitor: Monitor) -> Workspace {
    getOrCreateMonitorViewportFallbackWorkspace(
        projectId: activeWorkspaceProjectId(for: monitor),
        for: monitor,
    )
}

@MainActor func getOrCreateMonitorViewportFallbackWorkspace(projectId: WorkspaceProjectId, for monitor: Monitor) -> Workspace {
    getOrCreateFallbackWorkspace(
        projectId: projectId,
        monitor: monitor,
        excluding: nil,
    )
}

@MainActor func getOrCreateMonitorViewportFallbackWorkspace(
    projectId: WorkspaceProjectId,
    for monitor: Monitor,
    excluding excludedWorkspace: Workspace?,
) -> Workspace {
    getOrCreateFallbackWorkspace(
        projectId: projectId,
        monitor: monitor,
        excluding: excludedWorkspace,
    )
}

@MainActor
func getOrCreateMonitorViewportFallbackWorkspace(forPoint point: CGPoint) -> Workspace {
    let monitor = point.monitorApproximation
    return getOrCreateFallbackWorkspace(
        projectId: activeWorkspaceProjectId(for: monitor),
        monitor: monitor,
        excluding: nil,
    )
}

@MainActor
func getOrCreateFallbackWorkspace(
    projectId: WorkspaceProjectId,
    monitor: Monitor,
    excluding excludedWorkspace: Workspace?,
) -> Workspace {
    let scope = WorkspaceScope(projectId: projectId)
    if let workspaceId = retainedEmptyWorkspaceId(in: scope),
       let workspace = runtime.workspaces.workspaceById[workspaceId],
       workspace != excludedWorkspace,
       workspaceIsAvailableForMonitor(workspace, monitor: monitor)
    {
        return workspace
    }
    if let workspace = projectWorkspaces(projectId: projectId)
        .first(where: {
            $0 != excludedWorkspace &&
                $0.isEffectivelyEmpty &&
                !$0.isArchived &&
                workspaceIsAvailableForMonitor($0, monitor: monitor)
        })
    {
        return workspace
    }
    let workspace = Workspace.get(byName: nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor))
    workspace.markAsAutomaticallyNamed()
    workspace.assignProject(projectId)
    workspace.seedMonitorIfNeeded(monitor)
    return workspace
}

@MainActor
func projectWorkspaces(projectId: WorkspaceProjectId) -> [Workspace] {
    guard let project = runtime.workspaces.projectsById[projectId] else { return [] }
    let indexedWorkspaces = project.workspaceOrder
        .compactMap { runtime.workspaces.workspaceById[$0] }
        .filter { $0.projectId == projectId }
    if !indexedWorkspaces.isEmpty {
        return indexedWorkspaces
    }
    return Workspace.all
        .filter { $0.projectId == projectId }
        .sorted()
}

@MainActor
func orderedWorkspaces(in scope: WorkspaceScope) -> [Workspace] {
    orderWorkspacesByDisplayIndex(projectWorkspaces(projectId: scope.projectId)
        .filter { !$0.isArchived })
}

@MainActor
func orderedWorkspaces(in projectId: WorkspaceProjectId) -> [Workspace] {
    orderWorkspacesByDisplayIndex(projectWorkspaces(projectId: projectId)
        .filter { !$0.isArchived })
}

@MainActor
func orderedWorkspacesForPresentation() -> [Workspace] {
    var seen: Set<WorkspaceId> = []
    var result: [Workspace] = []
    for project in workspaceProjects() {
        for workspaceId in project.workspaceOrder {
            guard let workspace = runtime.workspaces.workspaceById[workspaceId],
                  !workspace.isArchived,
                  seen.insert(workspaceId).inserted
            else { continue }
            result.append(workspace)
        }
    }
    result.append(contentsOf: Workspace.all.filter { !$0.isArchived && seen.insert($0.id).inserted })
    for projectId in Set(result.map(\.projectId)) {
        let slots = result.indices.filter { result[$0].projectId == projectId }
        let ordered = orderWorkspacesByDisplayIndex(slots.map { result[$0] })
        for (slot, workspace) in zip(slots, ordered) { result[slot] = workspace }
    }
    return result
}

// Restoration preserves displayed numbers independently of registry insertion order.
// Sort numbered slots within each project while leaving custom-named slots in place.
@MainActor
private func orderWorkspacesByDisplayIndex(_ workspaces: [Workspace]) -> [Workspace] {
    let numbered = workspaces.enumerated().compactMap { offset, workspace -> (offset: Int, workspace: Workspace, index: Int)? in
        guard workspace.usesAutomaticDisplayName,
              let index = workspace.isConfiguredPersistent
                ? parsePositiveWorkspaceDisplayIndex(workspace.name)
                : workspace.restoredDisplayIndex else { return nil }
        return (offset, workspace, index)
    }
    let sorted = numbered.sorted {
        $0.index == $1.index ? $0.offset < $1.offset : $0.index < $1.index
    }
    var result = workspaces
    for (slot, value) in zip(numbered, sorted) { result[slot.offset] = value.workspace }
    return result
}
