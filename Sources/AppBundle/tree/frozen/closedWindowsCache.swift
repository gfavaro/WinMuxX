import AppKit
import Common

struct FrozenMonitor: Codable, Equatable, Sendable {
    let displayUUID: String?
    let topLeftCorner: CGPoint
    let visibleWorkspace: String

    @MainActor init(_ monitor: Monitor) {
        displayUUID = monitor.displayUUID
        topLeftCorner = monitor.rect.topLeftCorner
        visibleWorkspace = monitor.activeWorkspace.name
    }

    func resolve(in monitors: [Monitor]) -> Monitor? {
        if let displayUUID {
            return monitors.filter { $0.displayUUID == displayUUID }.singleOrNil()
        }
        // Old snapshots and displays without a UUID retain the coordinate fallback.
        return monitors.filter { $0.rect.topLeftCorner == topLeftCorner }.singleOrNil()
    }

    func preferredPoint(in monitors: [Monitor]) -> CGPoint {
        resolve(in: monitors)?.rect.topLeftCorner ?? topLeftCorner
    }
}

struct FrozenWorkspace: Codable, Equatable, Sendable {
    let name: String
    let projectId: WorkspaceProjectId
    let namingStyle: WorkspaceNamingStyle
    let displayIndex: Int?
    let monitor: FrozenMonitor // todo drop this property, once monitor to workspace assignment migrates to TreeNode
    let rootTilingNode: FrozenContainer
    let floatingWindows: [FrozenWindow]
    let macosUnconventionalWindows: [FrozenWindow]
    let arrangement: WorkspaceLayoutName?
    let preservesTopLevelGroups: Bool?
    let scrollingOffset: CGFloat?
    let scrollingAnchorIdentity: RestartWindowIdentity?
    let scrollingAnchorFrozenID: UInt32?
    let scrollingAnchorViewportPosition: CGFloat?
    let masterGroupIndex: Int?
    let masterRatio: CGFloat?
    let masterStackLayout: Layout?

    private enum CodingKeys: String, CodingKey {
        case name
        case projectId
        case namingStyle
        case monitor
        case displayIndex
        case rootTilingNode
        case floatingWindows
        case macosUnconventionalWindows
        case arrangement
        case preservesTopLevelGroups
        case scrollingOffset
        case scrollingAnchorIdentity
        case scrollingAnchorFrozenID
        case scrollingAnchorViewportPosition
        case masterGroupIndex
        case masterRatio
        case masterStackLayout
    }

    @MainActor init(_ workspace: Workspace, assignmentFor window: Window? = nil) {
        name = workspace.name
        projectId = workspace.projectId
        namingStyle = workspace.namingStyle
        displayIndex = workspace.usesAutomaticDisplayName ? automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: focus.workspace) : nil
        monitor = FrozenMonitor(workspace.workspaceMonitor)
        arrangement = workspace.arrangement
        preservesTopLevelGroups = workspace.preservesTopLevelGroups
        scrollingOffset = workspace.scrollingOffset
        workspace.captureScrollingViewportAnchor()
        let anchor = workspace.scrollingAnchorWindowId.flatMap(Window.get(byId:))
        if let anchor {
            scrollingAnchorIdentity = anchor.restartIdentity
            scrollingAnchorFrozenID = anchor.windowId
            scrollingAnchorViewportPosition = workspace.scrollingAnchorViewportPosition
        } else {
            scrollingAnchorIdentity = nil
            scrollingAnchorFrozenID = nil
            scrollingAnchorViewportPosition = nil
        }
        masterGroupIndex = workspace.masterGroupIndex
        masterRatio = workspace.masterRatio
        masterStackLayout = workspace.masterStackLayout
        if let window {
            let frozen = FrozenWindow(window)
            let floating = window.parent is Workspace
            let tiled = window.parent is TilingContainer
            rootTilingNode = FrozenContainer(assignment: tiled ? frozen : nil, in: workspace.rootTilingContainer)
            floatingWindows = floating ? [frozen] : []
            macosUnconventionalWindows = !floating && !tiled ? [frozen] : []
            return
        }
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
        arrangement = try container.decodeIfPresent(WorkspaceLayoutName.self, forKey: .arrangement)
        preservesTopLevelGroups = try container.decodeIfPresent(Bool.self, forKey: .preservesTopLevelGroups)
        scrollingOffset = try container.decodeIfPresent(CGFloat.self, forKey: .scrollingOffset)
        scrollingAnchorIdentity = try container.decodeIfPresent(RestartWindowIdentity.self, forKey: .scrollingAnchorIdentity)
        scrollingAnchorFrozenID = try container.decodeIfPresent(UInt32.self, forKey: .scrollingAnchorFrozenID)
        scrollingAnchorViewportPosition = try container.decodeIfPresent(CGFloat.self, forKey: .scrollingAnchorViewportPosition)
        masterGroupIndex = try container.decodeIfPresent(Int.self, forKey: .masterGroupIndex)
        masterRatio = try container.decodeIfPresent(CGFloat.self, forKey: .masterRatio)
        masterStackLayout = try container.decodeIfPresent(Layout.self, forKey: .masterStackLayout)
    }
}

@MainActor func cacheClosedWindowIfNeeded() {
    let frozenWorld = snapshotCurrentFrozenWorld()
    if frozenWorld.windowIds.isSubset(of: runtime.recovery.closedWindows.windowIds) {
        return // already cached
    }
    runtime.recovery.closedWindows = frozenWorld
}

@MainActor
func replaceClosedWindowsCache(_ frozenWorld: FrozenWorld) {
    runtime.recovery.closedWindows = frozenWorld
}

@MainActor
func syncClosedWindowsCacheToCurrentWorld() {
    invalidateLateRestartTreeRestoration()
    runtime.recovery.closedWindows = snapshotCurrentFrozenWorld()
}

@MainActor func restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: Window) async throws -> Bool {
    // An empty cache is not a restoration: new-window rules must still run.
    guard !runtime.recovery.closedWindows.workspaces.isEmpty else { return false }
    return try await restoreFrozenWorldIfNeeded(runtime.recovery.closedWindows, newlyDetectedWindow: newlyDetectedWindow)
}

/// AX disappearing during screen lock is recoverable; a native close is not.
/// Invalidate old ID-only snapshots so a reused ID never inherits the closed window's state.
@MainActor func invalidateClosedWindowsCacheForNativeClosure(_ windowId: UInt32) {
    if runtime.recovery.closedWindows.windowIds.contains(windowId) { resetClosedWindowsCache() }
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
    let restoredWorkspaceNames = Set(frozenWorld.workspaces.map(\.name))

    for frozenWorkspace in frozenWorld.workspaces {
        let workspace = Workspace.get(byName: frozenWorkspace.name)
        workspace.arrangement = frozenWorkspace.arrangement ?? (frozenWorkspace.rootTilingNode.layout == .master ? .master : .dwindle)
        workspace.preservesTopLevelGroups = (frozenWorkspace.preservesTopLevelGroups ?? false) || workspace.arrangement != .dwindle
        workspace.scrollingOffset = frozenWorkspace.scrollingOffset ?? 0
        workspace.masterRatio = frozenWorkspace.masterRatio
        workspace.masterStackLayout = frozenWorkspace.masterStackLayout ?? .tiles
        workspace.assignProject(frozenWorkspace.projectId)
        workspace.restoreNamingStyle(frozenWorkspace.namingStyle)
        workspace.restoredDisplayIndex = frozenWorkspace.displayIndex
        if restoreVisibleWorkspaces || workspace.preferredMonitorPoint == nil {
            workspace.preferredMonitorPoint = frozenWorkspace.monitor.preferredPoint(in: monitors)
        }
        let frozenWindowById = collectFrozenWindows(frozenWorkspace)
        for frozenWindow in frozenWorkspace.floatingWindows {
            if let window = windowsById[frozenWindow.id] {
                applyFrozenWindowState(window, frozenWindow)
                window.bindAsFloatingWindow(to: workspace)
                await restoreFrozenFloatingSize(window, frozenWindow, on: workspace)
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
        workspace.transitionArrangement(to: frozenWorkspace.arrangement ??
            (frozenWorkspace.rootTilingNode.layout == .master ? .master : .dwindle))
        if workspace.arrangement == .scrolling,
           let position = frozenWorkspace.scrollingAnchorViewportPosition, position.isFinite,
           let anchoredFrozen = resolveScrollingAnchor(in: frozenWorkspace, frozenWindows: frozenWindowById),
           let anchoredWindow = windowsById[anchoredFrozen.id],
           let column = workspace.scrollingMetrics.columns.first(where: { $0.node === anchoredWindow.topLevelWorkspaceGroup }) {
            let metrics = workspace.scrollingMetrics
            workspace.scrollingOffset = metrics.clampedOffset(column.start + column.width / 2 - position * metrics.areaWidth)
            workspace.lastScrollingFocusWindowId = anchoredWindow.windowId
        } else if workspace.arrangement == .scrolling,
                  let fallback = workspace.mostRecentWorkspaceFocusableWindowRecursive,
                  let column = workspace.scrollingMetrics.columns.first(where: { $0.node === fallback.topLevelWorkspaceGroup }) {
            workspace.scrollingOffset = workspace.scrollingMetrics.revealedOffset(for: column, current: 0)
            workspace.lastScrollingFocusWindowId = fallback.windowId
        }
        if frozenWorkspace.arrangement == nil, workspace.rootTilingContainer.layout == .master {
            migrateLegacyMasterTree(workspace)
        } else {
            workspace.masterGroupIndex = frozenWorkspace.masterGroupIndex ?? 0
        }
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
        guard let targetMonitor = monitor.resolve(in: monitors) else { continue }
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

    container.isMasterStack = frozenContainer.isMasterStack ?? false
    container.scrollingColumnWidth = frozenContainer.scrollingColumnWidth
    container.masterRatio = frozenContainer.masterRatio
    container.masterStackLayout = frozenContainer.masterStackLayout
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
    window.scrollingColumnWidth = frozenWindow.scrollingColumnWidth
    window.isFullscreen = frozenWindow.isFullscreen
    window.noOuterGapsInFullscreen = frozenWindow.noOuterGapsInFullscreen
    window.layoutReason = frozenWindow.layoutReason
    if let frame = frozenWindow.workspacePreviewFrame,
       let valid = normalizedWorkspacePreviewFrame(frame, origin: .zero, desktopSize: CGSize(width: 1, height: 1), minimumVisibleSize: 0)
    {
        window.workspacePreviewFrame = valid
        window.preserveRestoredWorkspacePreview = true
    }
    (window as? MacWindow)?.restoreLearnedMinimum(
        frozenWindow.learnedMinimumSize,
        savedBundleId: frozenWindow.minimumEvidenceBundleId,
        generation: MinimumEvidenceGeneration(global: frozenWindow.minimumEvidenceGlobalGeneration,
                                              app: frozenWindow.minimumEvidenceAppGeneration)
    )
    if let size = frozenWindow.lastFloatingSize, validRestoredWindowSize(size) {
        window.lastFloatingSize = size
    }
    if let width = frozenWindow.singleWindowManualWidth, width.isFinite, width > 0 {
        window.singleWindowManualWidth = width
    }
}

@MainActor
func migrateLegacyMasterTree(_ workspace: Workspace) {
    let root = workspace.rootTilingContainer
    guard root.layout == .master else { return }
    workspace.masterRatio = root.masterRatio
    let stack = root.children.compactMap { $0 as? TilingContainer }.first(where: \.isMasterStack)
    if let stack {
        let groups = stack.children
        for group in groups {
            group.unbindFromParent()
            group.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
        stack.unbindFromParent()
        workspace.masterStackLayout = root.masterStackLayout ?? .tiles
    }
    workspace.masterGroupIndex = 0
    root.layout = .dwindle
    root.isMasterStack = false
}

func validRestoredWindowSize(_ size: CGSize) -> Bool {
    size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
}

@MainActor
func restoreFrozenFloatingSize(_ window: Window, _ frozen: FrozenWindow, on workspace: Workspace) async {
    guard let saved = frozen.lastFloatingSize, validRestoredWindowSize(saved),
          !window.isFullscreen,
          (try? await window.isMacosFullscreen) == false,
          (try? await window.isMacosMinimized) == false else { return }
    let available = workspace.workspaceMonitor.visibleRect.size
    guard validRestoredWindowSize(available) else { return }
    let fitted = CGSize(width: min(saved.width, available.width), height: min(saved.height, available.height))
    window.lastFloatingSize = fitted
    if let macWindow = window as? MacWindow {
        try? await macWindow.setAxFrameBlocking(nil, fitted)
    } else {
        window.setAxFrame(nil, fitted)
    }
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

private func resolveScrollingAnchor(in workspace: FrozenWorkspace, frozenWindows: [UInt32: FrozenWindow]) -> FrozenWindow? {
    if let id = workspace.scrollingAnchorFrozenID, let exact = frozenWindows[id] { return exact }
    guard let identity = workspace.scrollingAnchorIdentity else { return nil }
    let saved = Array(frozenWindows.values)
    let strengths = saved.map { $0.restartIdentity?.matchStrength(with: identity) ?? 0 }
    guard let best = strengths.max(), best > 0 else { return nil }
    let candidates = saved.indices.filter { strengths[$0] == best }
    guard candidates.count == 1 else { return nil }
    return saved[candidates[0]]
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
    invalidateLateRestartTreeRestoration()
    runtime.recovery.closedWindows = FrozenWorld(workspaces: [], monitors: [], windowIds: [])
}
