import AppKit

/// First line of defence against lock screen
///
/// When you lock the screen, all accessibility API becomes unobservable (all attributes become empty, window id
/// becomes nil, etc.) which tricks WinMux into thinking that all windows were closed.
/// That's why every time a window dies WinMux caches the "entire world" (unless window is already presented in the cache)
/// so that once the screen is unlocked, WinMux could restore windows to where they were
@MainActor private var closedWindowsCache = FrozenWorld(workspaces: [], monitors: [], windowIds: [])

struct FrozenMonitor: Codable, Sendable {
    let topLeftCorner: CGPoint
    let visibleWorkspace: String

    @MainActor init(_ monitor: Monitor) {
        topLeftCorner = monitor.rect.topLeftCorner
        visibleWorkspace = monitor.activeWorkspace.name
    }
}

struct FrozenWorkspace: Codable, Sendable {
    let name: String
    let projectId: WorkspaceProjectId
    let namingStyle: WorkspaceNamingStyle
    let displayIndex: Int?
    let monitor: FrozenMonitor // todo drop this property, once monitor to workspace assignment migrates to TreeNode
    let rootTilingNode: FrozenContainer
    let floatingWindows: [FrozenWindow]
    let macosUnconventionalWindows: [FrozenWindow]

    private enum CodingKeys: String, CodingKey {
        case name
        case projectId
        case namingStyle
        case monitor
        case displayIndex
        case rootTilingNode
        case floatingWindows
        case macosUnconventionalWindows
    }

    @MainActor init(_ workspace: Workspace) {
        name = workspace.name
        projectId = workspace.projectId
        namingStyle = workspace.namingStyle
        displayIndex = workspace.usesAutomaticDisplayName ? automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: focus.workspace) : nil
        monitor = FrozenMonitor(workspace.workspaceMonitor)
        rootTilingNode = FrozenContainer(workspace.rootTilingContainer)
        floatingWindows = workspace.floatingWindows.map(FrozenWindow.init)
        macosUnconventionalWindows =
            workspaceOwnedMinimizedWindows(workspace).map(FrozenWindow.init) +
            (workspace.existingMacOsNativeHiddenAppsWindowsContainer?.children.filterIsInstance(of: Window.self).map(FrozenWindow.init) ?? []) +
            (workspace.existingMacOsNativeFullscreenWindowsContainer?.children.filterIsInstance(of: Window.self).map(FrozenWindow.init) ?? [])
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        projectId = try container.decodeIfPresent(WorkspaceProjectId.self, forKey: .projectId) ?? workspaceProjectDefaultId
        namingStyle = try container.decodeIfPresent(WorkspaceNamingStyle.self, forKey: .namingStyle) ?? .explicit
        displayIndex = try container.decodeIfPresent(Int.self, forKey: .displayIndex)
        monitor = try container.decode(FrozenMonitor.self, forKey: .monitor)
        rootTilingNode = try container.decode(FrozenContainer.self, forKey: .rootTilingNode)
        floatingWindows = try container.decode([FrozenWindow].self, forKey: .floatingWindows)
        macosUnconventionalWindows = try container.decode([FrozenWindow].self, forKey: .macosUnconventionalWindows)
    }
}

@MainActor func cacheClosedWindowIfNeeded() {
    let frozenWorld = snapshotCurrentFrozenWorld()
    if frozenWorld.windowIds.isSubset(of: closedWindowsCache.windowIds) {
        return // already cached
    }
    closedWindowsCache = frozenWorld
}

@MainActor
func replaceClosedWindowsCache(_ frozenWorld: FrozenWorld) {
    closedWindowsCache = frozenWorld
}

@MainActor
func syncClosedWindowsCacheToCurrentWorld() {
    closedWindowsCache = snapshotCurrentFrozenWorld()
}

@MainActor func restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: Window) async throws -> Bool {
    // An empty cache is not a restoration: new-window rules must still run.
    guard !closedWindowsCache.workspaces.isEmpty else { return false }
    return try await restoreFrozenWorldIfNeeded(closedWindowsCache, newlyDetectedWindow: newlyDetectedWindow)
}

/// AX disappearing during screen lock is recoverable; a native close is not.
/// Invalidate old ID-only snapshots so a reused ID never inherits the closed window's state.
@MainActor func invalidateClosedWindowsCacheForNativeClosure(_ windowId: UInt32) {
    if closedWindowsCache.windowIds.contains(windowId) { resetClosedWindowsCache() }
}

@MainActor
func restoreFrozenWorldIfNeeded(_ frozenWorld: FrozenWorld, newlyDetectedWindow: Window, matchedWindows: [UInt32: Window]? = nil, restoreVisibleWorkspaces: Bool = true) async throws -> Bool {
    let windowsById = matchedWindows ?? Dictionary(uniqueKeysWithValues: Workspace.all.flatMap { $0.allLeafWindowsRecursive }.map { ($0.windowId, $0) })
    if !frozenWorld.windowIds.isEmpty {
        guard frozenWorld.workspaces.contains(where: {
            collectFrozenWindows($0).keys.contains { windowsById[$0] === newlyDetectedWindow }
        }) else { return false }
    }
    let monitors = monitors
    let topLeftCornerToMonitor = monitors.grouped { $0.rect.topLeftCorner }
    let restoredWorkspaceNames = Set(frozenWorld.workspaces.map(\.name))

    for frozenWorkspace in frozenWorld.workspaces {
        let workspace = Workspace.get(byName: frozenWorkspace.name)
        workspace.assignProject(frozenWorkspace.projectId)
        workspace.restoreNamingStyle(frozenWorkspace.namingStyle)
        workspace.restoredDisplayIndex = frozenWorkspace.displayIndex
        workspace.preferredMonitorPoint = frozenWorkspace.monitor.topLeftCorner
        let frozenWindowById = collectFrozenWindows(frozenWorkspace)
        for frozenWindow in frozenWorkspace.floatingWindows {
            if let window = windowsById[frozenWindow.id] {
                applyFrozenWindowState(window, frozenWindow)
                window.bindAsFloatingWindow(to: workspace)
            }
        }
        for frozenWindow in frozenWorkspace.macosUnconventionalWindows {
            if let window = windowsById[frozenWindow.id] {
                try await restoreFrozenUnconventionalWindow(window, frozenWindow, on: workspace)
            }
        }
        let prevRoot = workspace.rootTilingContainer // Save prevRoot into a variable to avoid it being garbage collected earlier than needed
        let potentialOrphans = prevRoot.allLeafWindowsRecursive
        prevRoot.unbindFromParent()
        restoreTreeRecursive(frozenContainer: frozenWorkspace.rootTilingNode, parent: workspace, index: INDEX_BIND_LAST, windowsById: windowsById)
        for window in (potentialOrphans - workspace.rootTilingContainer.allLeafWindowsRecursive) {
            if matchedWindows == nil, let frozenWindow = frozenWindowById[window.windowId] {
                if case .macos = frozenWindow.layoutReason {
                    try await restoreFrozenUnconventionalWindow(window, frozenWindow, on: workspace)
                    continue
                }
                applyFrozenWindowState(window, frozenWindow)
            }
            try await window.relayoutWindow(on: workspace, forceTile: true)
        }
    }

    for monitor in restoreVisibleWorkspaces ? frozenWorld.monitors : [] {
        guard let targetMonitor = topLeftCornerToMonitor[monitor.topLeftCorner]?.singleOrNil() else { continue }
        let targetWorkspace: Workspace
        if let existingVisibleWorkspace = Workspace.existing(byName: monitor.visibleWorkspace),
           restoredWorkspaceNames.contains(existingVisibleWorkspace.name)
        {
            targetWorkspace = existingVisibleWorkspace
        } else {
            targetWorkspace = getOrCreateMonitorViewportFallbackWorkspace(for: targetMonitor)
        }
        if targetMonitor.activeWorkspace != targetWorkspace {
            _ = targetMonitor.setActiveWorkspace(targetWorkspace)
        }
    }
    return true
}

@discardableResult
@MainActor
private func restoreTreeRecursive(frozenContainer: FrozenContainer, parent: NonLeafTreeNodeObject, index: Int, windowsById: [UInt32: Window]) -> Bool {
    let container = TilingContainer(
        parent: parent,
        adaptiveWeight: frozenContainer.weight,
        frozenContainer.orientation,
        frozenContainer.layout,
        index: index,
    )

    container.dwindleOrientation = frozenContainer.dwindleOrientation
    for child in frozenContainer.children {
        switch child {
            case .window(let w):
                // Apps can reopen in any order; a missing sibling must not block later windows.
                guard let window = windowsById[w.id] else { continue }
                applyFrozenWindowState(window, w)
                window.bind(to: container, adaptiveWeight: w.weight, index: INDEX_BIND_LAST)
            case .container(let c):
                // There is no reason to continue
                if !restoreTreeRecursive(frozenContainer: c, parent: container, index: INDEX_BIND_LAST, windowsById: windowsById) { return false }
        }
    }
    if container.children.count == frozenContainer.children.count {
        container.dwindleSplitRatios = frozenContainer.dwindleSplitRatios ?? []
        container.dwindleChildRatios = frozenContainer.dwindleChildRatios
    }
    return true
}

@MainActor
func applyFrozenWindowState(_ window: Window, _ frozenWindow: FrozenWindow) {
    window.isFullscreen = frozenWindow.isFullscreen
    window.noOuterGapsInFullscreen = frozenWindow.noOuterGapsInFullscreen
    window.layoutReason = frozenWindow.layoutReason
    (window as? MacWindow)?.restoreLearnedMinimum(frozenWindow.learnedMinimumSize)
}

@MainActor
func restoreFrozenUnconventionalWindow(
    _ window: Window,
    _ frozenWindow: FrozenWindow,
    on workspace: Workspace,
) async throws {
    applyFrozenWindowState(window, frozenWindow)

    let isMacosFullscreen = try await window.isMacosFullscreen
    let isMacosMinimized = try await (!isMacosFullscreen).andAsync { @MainActor @Sendable in try await window.isMacosMinimized }
    let isMacosWindowOfHiddenApp = !isMacosFullscreen && !isMacosMinimized &&
        !config.automaticallyUnhideMacosHiddenApps && (window.app as? MacApp)?.nsApp.isHidden == true

    switch true {
        case isMacosFullscreen:
            window.bind(to: workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
        case isMacosMinimized:
            window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        case isMacosWindowOfHiddenApp:
            window.bind(to: workspace.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
        default:
            switch frozenWindow.layoutReason {
                case .macos(let prevParentKind, let prevWorkspaceName):
                    try await exitMacOsNativeUnconventionalState(
                        window: window,
                        prevParentKind: prevParentKind,
                        prevWorkspaceName: prevWorkspaceName,
                        workspace: workspace,
                    )
                case .standard:
                    window.bindAsFloatingWindow(to: workspace)
            }
    }
}

func collectFrozenWindows(_ frozenWorkspace: FrozenWorkspace) -> [UInt32: FrozenWindow] {
    var result = [UInt32: FrozenWindow]()
    for frozenWindow in frozenWorkspace.floatingWindows {
        result[frozenWindow.id] = frozenWindow
    }
    for frozenWindow in frozenWorkspace.macosUnconventionalWindows {
        result[frozenWindow.id] = frozenWindow
    }
    collectFrozenWindowsRecursive(frozenWorkspace.rootTilingNode, result: &result)
    return result
}

private func collectFrozenWindowsRecursive(_ frozenContainer: FrozenContainer, result: inout [UInt32: FrozenWindow]) {
    for child in frozenContainer.children {
        switch child {
            case .window(let frozenWindow):
                result[frozenWindow.id] = frozenWindow
            case .container(let container):
                collectFrozenWindowsRecursive(container, result: &result)
        }
    }
}

// Consider the following case:
// 1. Close window
// 2. The previous step lead to caching the whole world
// 3. Change something in the layout
// 4. Lock the screen
// 5. The cache won't be updated because all alive windows are already cached
// 6. Unlock the screen
// 7. The wrong cache is used
//
// That's why we have to refresh the cache every time layout or visible workspace assignment changes. Those changes can
// be caused by running commands and with mouse manipulations.
@MainActor func resetClosedWindowsCache() {
    closedWindowsCache = FrozenWorld(workspaces: [], monitors: [], windowIds: [])
}
