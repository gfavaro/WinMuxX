enum WindowDragIntentKind: Equatable {
    case tabStack(targetWindowId: UInt32)
    /// Into the Tabbed workspace bar showing the target window, at `index` among its tabs.
    case insertTab(targetWindowId: UInt32, index: Int)
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
    switch kind {
        case .tabStack(let targetWindowId):
            // A Tabbed workspace's bars show whatever the window tabs setting, and so do their groups.
            return config.windowTabs.enabled || Window.get(byId: targetWindowId)?.nodeWorkspace?.arrangement == .tabbed
        case .insertTab:
            return true
        case .reorderTab(let windowId, _):
            return config.windowTabs.enabled || Window.get(byId: windowId)?.nodeWorkspace?.arrangement == .tabbed
        case .createWorkspace, .sidebarHover, .detachTab, .stackSplit, .swap, .moveToWorkspace, .moveToWorkspaceZone:
            return true
    }
}
