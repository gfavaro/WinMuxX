enum WindowDragIntentKind: Equatable {
    case tabStack(targetWindowId: UInt32)
    case reorderTab(windowId: UInt32, targetIndex: Int)
    case detachTab(windowId: UInt32)
    case stackSplit(targetWindowId: UInt32, position: WindowStackSplitPosition)
    case swap(targetWindowId: UInt32)
    case moveToWorkspace(workspaceName: String)
    case moveToWorkspaceZone(workspaceName: String, zone: WindowDropZone)
    case createWorkspace(projectId: WorkspaceProjectId? = nil, monitorScopeId: String? = nil)
    case sidebarHover
}

@MainActor
func isWindowDragIntentKindEnabled(_ kind: WindowDragIntentKind) -> Bool {
    if runtime.workspaceBackend.kind == .native {
        // Native stacks tabbed groups but not Accordion yet, and macOS owns desktops.
        switch kind {
            case .swap, .stackSplit, .moveToWorkspace, .moveToWorkspaceZone: return true
            case .tabStack, .reorderTab, .detachTab: return config.windowTabs.enabled && config.dragStackLayout == .tabGroup
            case .createWorkspace, .sidebarHover: return false
        }
    }
    switch kind {
        case .tabStack, .reorderTab:
            return config.windowTabs.enabled
        case .detachTab, .stackSplit, .swap, .moveToWorkspace, .moveToWorkspaceZone, .createWorkspace, .sidebarHover:
            return true
    }
}
