@MainActor
func buildWorkspaceSidebarWorkspaceViewModels(
    currentFocus: LiveFocus,
    workspaceLabels: [String: String],
    availableMonitors: [Monitor],
) async -> [WorkspaceSidebarWorkspaceViewModel] {
    var workspaces: [WorkspaceSidebarWorkspaceViewModel] = []
    var seenNames = Set<String>()
    for workspace in orderedWorkspacesForPresentation() {
        // SwiftUI uses the workspace name as the row identity. A stale or
        // duplicated workspace entry must not produce two rows with the same
        // identity (which makes the sidebar visually duplicate/reorder rows).
        guard seenNames.insert(workspace.name).inserted else { continue }
        workspaces.append(await makeWorkspaceSidebarWorkspaceViewModel(
            workspace,
            currentFocus: currentFocus,
            workspaceLabels: workspaceLabels,
            availableMonitors: availableMonitors,
        ))
    }
    return workspaces
}

@MainActor
private func makeWorkspaceSidebarWorkspaceViewModel(
    _ workspace: Workspace,
    currentFocus: LiveFocus,
    workspaceLabels: [String: String],
    availableMonitors: [Monitor],
) async -> WorkspaceSidebarWorkspaceViewModel {
    let workspaceMonitor = workspace.workspaceMonitor
    return WorkspaceSidebarWorkspaceViewModel(
        name: workspace.name,
        projectId: workspace.projectId,
        displayName: sidebarWorkspaceDisplayName(
            workspace.name,
            labels: workspaceLabels,
            displayIndex: automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: currentFocus.workspace)
        ),
        sidebarLabel: workspaceLabels[workspace.name] ?? "",
        isGeneratedName: isSidebarDraftWorkspaceName(workspace.name) || workspace.usesAutomaticDisplayName,
        monitorScopeId: workspaceSidebarMonitorScopeId(for: workspaceMonitor),
        monitorName: availableMonitors.count > 1 ? workspaceMonitor.name : nil,
        isFocused: currentFocus.workspace == workspace,
        isVisible: workspace.isVisible,
        items: await buildWorkspaceSidebarItems(for: workspace, currentFocus: currentFocus),
    )
}

@MainActor
func sidebarWorkspaceDisplayName(_ name: String, labels: [String: String], displayIndex: Int? = nil) -> String {
    if let label = labels[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { return label }
    if let displayIndex { return "Workspace \(displayIndex)" }
    if parsePositiveWorkspaceDisplayIndex(name) != nil { return "Workspace \(name)" }
    return workspaceDefaultDisplayName(name)
}

func visibleWorkspaceNamesForSidebar(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    selectedMonitorScopeId: String,
    focusedMonitorScopeId: String,
) -> Set<String> {
    Set(workspaces.filter {
        workspaceSidebarWorkspaceMatchesScope(
            $0,
            selectedScopeId: selectedMonitorScopeId,
            focusedMonitorScopeId: focusedMonitorScopeId,
        )
    }.map(\.name))
}
