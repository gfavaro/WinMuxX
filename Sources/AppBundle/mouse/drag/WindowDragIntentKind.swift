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
    let capabilities = runtime.workspaceBackend.capabilities
    switch kind {
        case .tabStack, .reorderTab:
            return config.windowTabs.enabled
        // With native Spaces macOS creates desktops, and hovering does not switch them.
        case .createWorkspace:
            return capabilities.ownsWorkspaceLifecycle
        case .sidebarHover:
            return capabilities.activatesWorkspaces
        case .detachTab, .stackSplit, .swap, .moveToWorkspace, .moveToWorkspaceZone:
            return true
    }
}
