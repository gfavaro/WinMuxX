import AppKit
import Common
import NativeSpaces

public final class TrayMenuModel: ObservableObject {
    @MainActor public static let shared = TrayMenuModel()

    init() {}

    @Published var modePresentation: ModePresentation?
    @Published var menuBarWorkspaceIndicator: String = "1"
    @Published var menuBarWorkspaceName: String = ""
    @Published var menuBarWorkspaceArrangement: WorkspaceLayoutName = .dwindle
    /// Why native tiling has stopped until something outside WinMuxX changes.
    @Published var menuBarTilingStoppedReason: String? = nil
    /// Is "layouting" enabled
    @Published var isEnabled: Bool = true
    @Published var shortcutHealth: ShortcutHealth = .available
    @Published var workspaces: [WorkspaceViewModel] = []
    @Published var workspaceSidebarWorkspaces: [WorkspaceSidebarWorkspaceViewModel] = []
    @Published var workspaceSidebarConfiguration: WorkspaceSidebarConfiguration = .empty
    @Published var workspaceSidebarWallpaperRefreshGeneration: UInt64 = 0
    @Published var workspaceSidebarProjects: [WorkspaceSidebarProjectViewModel] = []
    @Published var workspaceSidebarActiveProjectId: WorkspaceProjectId = workspaceProjectDefaultId
    @Published var workspaceSidebarMonitorScopes: [WorkspaceSidebarMonitorScopeViewModel] = []
    /// Panel-local UI state. The shared model keeps this only as a compatibility default for legacy callers.
    @Published var workspaceSidebarSelectedMonitorScopeId: String = workspaceSidebarDefaultScopeId
    @Published var workspaceSidebarTargetMonitorScopeId: String = workspaceSidebarDefaultScopeId
    @Published var workspaceSidebarFocusedMonitorScopeId: String = ""
    @Published var workspaceSidebarShowsMonitorSelector: Bool = false
    @Published var workspaceSidebarDropPreview: WorkspaceSidebarDropPreviewViewModel? = nil
    @Published var windowTabStrips: [WindowTabStripViewModel] = []
    @Published var isWorkspaceSidebarExpanded: Bool = false { didSet { if oldValue != isWorkspaceSidebarExpanded { MainActor.assumeIsolated { requestPublicStateUpdate() } } } }
    @Published var workspaceSidebarVisibleWidth: CGFloat = 0
    /// Panel-local: whether the sidebar's view tree exists. See WorkspaceSidebarPanel.loadContent.
    @Published var workspaceSidebarContentLoaded: Bool = true
    @Published var workspaceSidebarTopPadding: CGFloat = 12
    @Published var workspaceSidebarHoveredWorkspaceName: String? = nil
    @Published var menuBarConfiguration = MenuBarConfig()

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

extension ObservableObject {
    /// Assigning a @Published property fires objectWillChange even when the value is unchanged,
    /// re-rendering every observing view (menu bar label, sidebar panels, tab strips). Models
    /// republished wholesale on every refresh session must equality-guard their writes.
    /// Returns whether the value actually changed, for callers that need to chain side effects.
    @discardableResult
    func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<Self, T>, _ value: T) -> Bool {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
            return true
        }
        return false
    }
}

@MainActor func updateTrayText() {
    if runtime.workspaceBackend.ui.updateTray() { return }
    let focus = focus
    let workspace = focus.workspace
    let number = automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: workspace)
        ?? Int(workspace.name)
        ?? userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: workspace)
            .filter { $0.projectId == workspace.projectId }.firstIndex(of: workspace).map { $0 + 1 }
        ?? 1
    let persistentLabel = workspace.isConfiguredPersistent && parsePositiveWorkspaceDisplayIndex(workspace.name) == nil ? workspace.name : nil
    TrayMenuModel.shared.setIfChanged(\.menuBarWorkspaceIndicator, menuBarWorkspaceIndicator(label: config.workspaceSidebar.workspaceLabels[workspace.name] ?? persistentLabel, number: number))
    TrayMenuModel.shared.setIfChanged(\.menuBarWorkspaceName, workspaceDisplayName(workspace.name))
    TrayMenuModel.shared.setIfChanged(\.menuBarWorkspaceArrangement, workspace.arrangement)
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
    TrayMenuModel.shared.setIfChanged(\.workspaces, workspaces)

}

/// The tray indicator for native Spaces: the desktop number, its name and tiling state.
@MainActor func updateNativeTrayText() {
    let displays = nativeObservedDisplays() ?? []
    let display = displays.first { $0.identifier == focus.workspace.workspaceMonitor.displayUUID } ?? displays.first
    let number = display.flatMap { NativeSpaceNavigation.activeDesktopNumber(on: $0.identifier, in: displays) }
    TrayMenuModel.shared.setIfChanged(\.menuBarWorkspaceIndicator, number.map(String.init) ?? "Spaces")
    let state = runtime.workspaceBackend.native.tilingEnabled ? runtime.workspaceBackend.native.tiling.status : "Observation only"
    let place = display == nil ? "Native Spaces unavailable" : number.map { nativeDesktopDisplayName($0) } ?? "Fullscreen App"
    TrayMenuModel.shared.setIfChanged(\.menuBarWorkspaceName, "\(place) · \(state)")
    TrayMenuModel.shared.setIfChanged(\.menuBarWorkspaceArrangement, focus.workspace.arrangement)
    let tiling = runtime.workspaceBackend.native.tiling
    TrayMenuModel.shared.setIfChanged(\.menuBarTilingStoppedReason, runtime.workspaceBackend.native.tilingEnabled && tiling.isStopped ? tiling.status : nil)
}
