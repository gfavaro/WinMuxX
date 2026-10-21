enum WorkspaceSidebarSearchSelection: Hashable {
    case workspace(String)
    case window(UInt32)
}

func workspaceSidebarSearchSelections(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    includeWorkspaceHeaders: Bool = false,
) -> [WorkspaceSidebarSearchSelection] {
    workspaces.flatMap { workspace in
        let itemSelections = workspace.items.flatMap { item -> [WorkspaceSidebarSearchSelection] in
            switch item.kind {
                case .window(let window):
                    return [.window(window.windowId)]
                case .tabGroup(let group):
                    return (group.searchVisibleTabs ?? group.tabs).map { .window($0.windowId) }
            }
        }
        return includeWorkspaceHeaders || itemSelections.isEmpty
            ? [.workspace(workspace.name)] + itemSelections : itemSelections
    }
}

func workspaceSidebarInitialNavigationSelection(workspaces: [WorkspaceSidebarWorkspaceViewModel]) -> WorkspaceSidebarSearchSelection? {
    let focused = workspaces.first(where: \.isFocused)
    return (focused ?? workspaces.first).map { .workspace($0.name) }
}

func workspaceSidebarSelectionAfterMoving(_ selected: WorkspaceSidebarSearchSelection?,
                                        selections: [WorkspaceSidebarSearchSelection], delta: Int) -> WorkspaceSidebarSearchSelection? {
    guard !selections.isEmpty else { return nil }
    guard let selected, let index = selections.firstIndex(of: selected) else {
        return delta < 0 ? selections.last : selections.first
    }
    return selections[max(0, min(selections.count - 1, index + delta))]
}
