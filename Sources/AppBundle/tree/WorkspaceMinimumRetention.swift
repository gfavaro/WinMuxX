import Common

/// Choose only the additional empty slots required by the global minimum.
/// Existing lifecycle guarantees count first, independent of presentation filters.
@MainActor
func minimumWorkspaceRetentionIds() -> Set<WorkspaceId> {
    let ordered = orderedWorkspacesForPresentation().filter { !$0.isArchived }
    let retained = retainedEmptyWorkspaceIdsByScope()
    let existingSurvivors = ordered.filter {
        workspaceShouldSurviveReconciliation($0, retainedEmptyWorkspaceIds: retained)
    }
    let needed = max(0, config.effectiveMinimumWorkspaceCount - existingSurvivors.count)
    let survivorIds = Set(existingSurvivors.map(\.id))
    let candidates = ordered.filter { !survivorIds.contains($0.id) }
    // Reuse a displayed empty slot before another spare, preserving focus whenever
    // the configured minimum still has room for an empty workspace.
    let prioritized = candidates.filter(\.isVisible) + candidates.filter { !$0.isVisible }
    return Set(prioritized.prefix(needed).map(\.id))
}

@MainActor
func ensureConfiguredMinimumWorkspaces() {
    let existing = Workspace.all.filter { !$0.isArchived }.count
    let missing = max(0, config.effectiveMinimumWorkspaceCount - existing)
    for _ in 0..<missing {
        _ = createBlankWorkspace(projectId: workspaceProjectDefaultId, monitor: mainMonitor)
    }
}
