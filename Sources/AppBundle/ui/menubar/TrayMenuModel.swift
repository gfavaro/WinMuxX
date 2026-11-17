import AppKit
import Observation
import Common
import Observation

@Observable

public final class TrayMenuModel {
    @MainActor public static let shared = TrayMenuModel()

    init() {}

    var modePresentation: ModePresentation?
    var menuBarWorkspaceIndicator: String = "1"
    var menuBarWorkspaceName: String = ""
    var menuBarWorkspaceArrangement: WorkspaceLayoutName = .dwindle
    /// Is "layouting" enabled
    var isEnabled: Bool = true
    var shortcutHealth: ShortcutHealth = .available
    var workspaces: [WorkspaceViewModel] = []
    var workspaceSidebarWorkspaces: [WorkspaceSidebarWorkspaceViewModel] = []
    var workspaceSidebarConfiguration: WorkspaceSidebarConfiguration = .empty
    var workspaceSidebarWallpaperRefreshGeneration: UInt64 = 0
    var workspaceSidebarProjects: [WorkspaceSidebarProjectViewModel] = []
    var workspaceSidebarActiveProjectId: WorkspaceProjectId = workspaceProjectDefaultId
    var workspaceSidebarMonitorScopes: [WorkspaceSidebarMonitorScopeViewModel] = []
    /// Panel-local UI state. The shared model keeps this only as a compatibility default for legacy callers.
    var workspaceSidebarSelectedMonitorScopeId: String = workspaceSidebarDefaultScopeId
    var workspaceSidebarTargetMonitorScopeId: String = workspaceSidebarDefaultScopeId
    var workspaceSidebarFocusedMonitorScopeId: String = ""
    var workspaceSidebarShowsMonitorSelector: Bool = false
    var workspaceSidebarDropPreview: WorkspaceSidebarDropPreviewViewModel? = nil
    var windowTabStrips: [WindowTabStripViewModel] = []
    var isWorkspaceSidebarExpanded: Bool = false { didSet { if oldValue != isWorkspaceSidebarExpanded { MainActor.assumeIsolated { requestPublicStateUpdate() } } } }
    var workspaceSidebarVisibleWidth: CGFloat = 0
    /// Panel-local: whether the sidebar's view tree exists. See WorkspaceSidebarPanel.loadContent.
    var workspaceSidebarContentLoaded: Bool = true
    var workspaceSidebarTopPadding: CGFloat = 12
    var workspaceSidebarHoveredWorkspaceName: String? = nil
    var menuBarConfiguration = MenuBarConfig()

    var visibleWorkspaceSidebarWorkspaces: [WorkspaceSidebarWorkspaceViewModel] {
        workspaceSidebarWorkspaces.filter {
            $0.projectId == workspaceSidebarActiveProjectId &&
            workspaceSidebarWorkspaceMatchesScope(
                $0,
                selectedScopeId: workspaceSidebarSelectedMonitorScopeId,
                focusedMonitorScopeId: workspaceSidebarFocusedMonitorScopeId,
            )
        }
    }

}

@MainActor func updateTrayText() {
    let focus = focus
    let workspace = focus.workspace
    let number = automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: workspace)
        ?? Int(workspace.name)
        ?? userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: workspace)
            .filter { $0.projectId == workspace.projectId }.firstIndex(of: workspace).map { $0 + 1 }
        ?? 1
    let persistentLabel = workspace.isConfiguredPersistent && parsePositiveWorkspaceDisplayIndex(workspace.name) == nil ? workspace.name : nil
    TrayMenuModel.shared.menuBarWorkspaceIndicator = menuBarWorkspaceIndicator(label: config.workspaceSidebar.workspaceLabels[workspace.name] ?? persistentLabel, number: number)
    TrayMenuModel.shared.menuBarWorkspaceName = workspaceDisplayName(workspace.name)
    TrayMenuModel.shared.menuBarWorkspaceArrangement = workspace.arrangement
    let workspaces = userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).filter {
        $0.projectId == activeWorkspaceProjectId(for: $0.workspaceMonitor)
    }.map {
        let apps = $0.allLeafWindowsRecursive.map { $0.app.name?.takeIf { !$0.isEmpty } }.filterNotNil().toSet()
        let dash = " - "
        let suffix = switch true {
            case !apps.isEmpty: dash + apps.sorted().joinTruncating(separator: ", ", length: 25)
            default: ""
        }
        let hasFullscreenWindows = $0.allLeafWindowsRecursive.contains { $0.isFullscreen }
        return WorkspaceViewModel(
            name: $0.name,
            displayName: workspaceDisplayName($0.name),
            suffix: suffix,
            isFocused: focus.workspace == $0,
            isEffectivelyEmpty: !workspaceHasSidebarVisibleWindows($0),
            isVisible: $0.isVisible,
            hasFullscreenWindows: hasFullscreenWindows,
        )
    }
    TrayMenuModel.shared.workspaces = workspaces
}
