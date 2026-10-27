import AppKit
import Common

extension Workspace {
    @MainActor
    func layoutWorkspace() async throws {
        await WorkspacePresentationController.shared.restorePendingFloatingFrames(in: self)
        if WorkspacePresentationController.shared.preservesLayout(for: self) { return }
        applyConfiguredLayout()
        if runtime.workspaceBackend.kind == .native, !supportsNativeTiling {
            throw NativeTilingUnsupportedLayout()
        }
        normalizeMasterLayout()
        if isEffectivelyEmpty { return }
        let rect = workspaceTilingRect(self)
        let context = LayoutContext(self)
        if let tabGroup = rootTilingContainer.allTabbedContainersRecursive.first(where: \.hasFullscreenTab) {
            WorkspaceScrollingGestureController.shared.cancelForWorkspaceChange(self)
            ScrollingWindowOrdering.shared.cancel()
            WorkspaceScrollingMinimap.shared.dismiss()
            lastAppliedLayoutPhysicalRect = rect
            lastAppliedLayoutVirtualRect = rect
            rootTilingContainer.lastAppliedLayoutPhysicalRect = rect
            rootTilingContainer.lastAppliedLayoutVirtualRect = rect
            tabGroup.lastAppliedLayoutPhysicalRect = rect
            tabGroup.lastAppliedLayoutVirtualRect = rect
            try await hideAllWindowsExcept(tabGroup)
            try await tabGroup.layoutRecursive(rect.topLeftCorner, width: rect.width, height: rect.height, virtual: rect, context)
            return
        }
        if let fullscreenWindow = rootTilingContainer.mostRecentWindowRecursive, fullscreenWindow.isFullscreen {
            WorkspaceScrollingGestureController.shared.cancelForWorkspaceChange(self)
            ScrollingWindowOrdering.shared.cancel()
            WorkspaceScrollingMinimap.shared.dismiss()
            lastAppliedLayoutPhysicalRect = rect
            lastAppliedLayoutVirtualRect = rect
            rootTilingContainer.lastAppliedLayoutPhysicalRect = rect
            rootTilingContainer.lastAppliedLayoutVirtualRect = rect
            try await hideAllWindowsExcept(fullscreenWindow)
            fullscreenWindow.lastAppliedLayoutVirtualRect = rect
            fullscreenWindow.lastAppliedLayoutPhysicalRect = nil
            try await fullscreenWindow.layoutFullscreen(context)
            return
        }
        if arrangement == .master || arrangement == .scrolling {
            lastAppliedLayoutPhysicalRect = rect
            lastAppliedLayoutVirtualRect = rect
            rootTilingContainer.lastAppliedLayoutPhysicalRect = rect
            rootTilingContainer.lastAppliedLayoutVirtualRect = rect
            try await layoutWorkspaceGroups(in: rect, context)
            for window in children.filterIsInstance(of: Window.self) {
                window.lastAppliedLayoutPhysicalRect = nil
                window.lastAppliedLayoutVirtualRect = nil
                try await window.layoutFloatingWindow(context)
            }
            return
        }
        // If monitors are aligned vertically and the monitor below has smaller width, then macOS may not allow the
        // window on the upper monitor to take full width. rect.height - 1 resolves this problem
        // But I also faced this problem in monitors horizontal configuration. ¯\_(ツ)_/¯
        try await layoutRecursive(rect.topLeftCorner, width: rect.width, height: rect.height - 1, virtual: rect, context)
    }
}

struct NativeTilingUnsupportedLayout: Error, CustomStringConvertible {
    var description: String { "Native tiling currently supports Dwindle/Master and non-overlapping tile groups; retained unsupported groups were not modified" }
}

extension Workspace {
    @MainActor var supportsNativeTiling: Bool {
        func supported(_ container: TilingContainer) -> Bool {
            // Tabbed groups stack their tabs at one frame and Accordion overlaps them;
            // either way the active window is raised, see raiseCoveredNativeTabs.
            [.tiles, .dwindle, .tabGroup, .stacked].contains(container.layout) &&
                container.children.allSatisfy {
                guard let nested = $0 as? TilingContainer else { return true }
                return supported(nested)
            }
        }
        // Scrolling keeps out-of-view columns at the display edges, never parked in a corner.
        return [.dwindle, .master, .scrolling].contains(arrangement) && masterStackLayout == .tiles && supported(rootTilingContainer)
    }
}

@MainActor
private func layoutWorkspaceGroups(in rect: Rect, _ context: LayoutContext) async throws {
    let workspace = context.workspace
    if workspace.arrangement == .scrolling {
        workspace.rebaseScrollingViewportIfNeeded(using: workspace.scrollingMetrics)
        let metrics = workspace.scrollingMetrics
        if !workspace.scrollingGestureMotionActive, let focused = focus.windowOrNil,
           workspace.lastScrollingFocusWindowId != focused.windowId,
           let column = metrics.columns.first(where: { $0.node === focused.topLevelWorkspaceGroup })
        {
            workspace.scrollingOffset = metrics.revealedOffset(for: column, current: workspace.scrollingOffset)
            workspace.lastScrollingFocusWindowId = focused.windowId
        }
        workspace.scrollingOffset = metrics.clampedOffset(workspace.scrollingOffset)
        if !workspace.scrollingGestureMotionActive, let window = focus.windowOrNil as? MacWindow,
           window.nodeWorkspace === workspace,
           let column = metrics.columns.first(where: { $0.node === window.topLevelWorkspaceGroup }) {
            let epoch = workspace.scrollingSessionEpoch
            let offsets = (try? await window.scrollingSheetOffsets()) ?? []
            try checkCancellation()
            if workspace.scrollingSessionEpoch == epoch, focus.windowOrNil === window,
               let left = offsets.map(\.minX).min(), let right = offsets.map(\.maxX).max() {
                let leafInset = (window.lastAppliedLayoutVirtualRect?.minX ?? 0) -
                    (column.node.lastAppliedLayoutVirtualRect?.minX ?? 0)
                workspace.scrollingOffset = metrics.revealedOffset(start: column.start + leafInset + left,
                    end: column.start + leafInset + right, current: workspace.scrollingOffset)
            }
        }
    }
    let frames = workspace.arrangementGroupFrames(in: rect, gaps: context.resolvedGaps)
    for frame in frames {
        for window in frame.node.allLeafWindowsRecursive {
            window.isConcealedByScrolling = workspace.arrangement == .scrolling &&
                !CGRect(origin: frame.virtual.topLeftCorner, size: frame.virtual.size)
                    .intersects(workspace.scrollingMetrics.geometry.area)
        }
        try await frame.node.layoutRecursive(frame.physical.topLeftCorner, width: frame.physical.width,
                                             height: frame.physical.height, virtual: frame.virtual, context)
    }
    if workspace.arrangement == .scrolling {
        workspace.captureScrollingViewportAnchor()
        ScrollingWindowOrdering.shared.update(workspace: workspace, frames: frames)
    }
}

extension TreeNode {
    @MainActor
    fileprivate func layoutRecursive(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        switch nodeCases {
            case .workspace(let workspace):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                try await workspace.rootTilingContainer.layoutRecursive(point, width: width, height: height, virtual: virtual, context)
                for window in workspace.children.filterIsInstance(of: Window.self) {
                    window.lastAppliedLayoutPhysicalRect = nil
                    window.lastAppliedLayoutVirtualRect = nil
                    try await window.layoutFloatingWindow(context)
                }
            case .window(let window):
                window.preserveRestoredWorkspacePreview = false
                if window.windowId != currentlyManipulatedWithMouseWindowId || isPinnedDraggedWindow(window.windowId) {
                    let previousPhysicalRect = lastAppliedLayoutPhysicalRect
                    lastAppliedLayoutVirtualRect = virtual
                    let isFullscreenTab = window.nearestWindowTabGroup?.hasFullscreenTab == true
                    if window.isFullscreen && !isFullscreenTab && window == context.workspace.rootTilingContainer.mostRecentWindowRecursive {
                        lastAppliedLayoutPhysicalRect = nil
                        try await window.layoutFullscreen(context)
                    } else {
                        lastAppliedLayoutPhysicalRect = physicalRect
                        if !isFullscreenTab {
                            window.isFullscreen = false
                        }
                        if window.isHiddenInCorner || !canReuseLastAppliedWindowFrame(previousPhysicalRect: previousPhysicalRect, nextPhysicalRect: physicalRect) {
                            try await WindowMotion.shared.apply(window, target: CGRect(origin: point, size: CGSize(width: width, height: height)))
                        }
                    }
                }
            case .tilingContainer(let container):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                if container.usesWindowTabBehavior {
                    debugFocusLog("layoutRecursive tabContainer=\(ObjectIdentifier(container)) physicalRect=\(physicalRect) virtualRect=\(virtual)")
                }
                switch container.layout {
                    case .tiles, .master:
                        try await container.layoutTiles(point, width: width, height: height, virtual: virtual, context)
                    case .dwindle:
                        try await container.layoutDwindle(point, width: width, height: height, virtual: virtual, context)
                    case .tabGroup, .stacked:
                        try await container.layoutTabGroup(point, width: width, height: height, virtual: virtual, context)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return // Nothing to do for weirdos
        }
    }
}

private func canReuseLastAppliedWindowFrame(previousPhysicalRect: Rect?, nextPhysicalRect: Rect) -> Bool {
    guard refreshSessionEvent?.canReuseLastAppliedWindowFrames == true else { return false }
    guard let previousPhysicalRect else { return false }
    // Repeated weight normalization can change fractions without changing the
    // whole-point frame sent to AX. Compare the actual native targets.
    let previous = CGRect(origin: previousPhysicalRect.topLeftCorner, size: previousPhysicalRect.size)
    let next = CGRect(origin: nextPhysicalRect.topLeftCorner, size: nextPhysicalRect.size)
    return windowMotionNativeTarget(previous) == windowMotionNativeTarget(next)
}

private struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps

    @MainActor
    init(_ workspace: Workspace) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    }
}

extension Window {
    @MainActor
    fileprivate func layoutFloatingWindow(_ context: LayoutContext) async throws {
        if runtime.workspaceBackend.kind == .native { return }
        // A failed corner restoration must retry from its saved position, rather
        // than treating the still-parked native frame as a cross-display move.
        guard !isHiddenInCorner else { return }
        preserveRestoredWorkspacePreview = false
        // With a single monitor the cross-monitor proportional move below is always a no-op,
        // so skip the AX round-trip it would need. This runs for every floating window on
        // every layout pass.
        if monitors.count == 1 {
            if isFullscreen {
                try await layoutFullscreen(context)
                isFullscreen = false
            }
            return
        }
        let workspace = context.workspace
        let windowRect = try await getAxRect() // Probably not idempotent
        let currentMonitor = windowRect?.center.monitorApproximation
        if let currentMonitor, let windowRect, workspace != currentMonitor.activeWorkspace {
            let windowTopLeftCorner = windowRect.topLeftCorner
            let xProportion = (windowTopLeftCorner.x - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
            let yProportion = (windowTopLeftCorner.y - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

            let workspaceRect = workspace.workspaceMonitor.visibleRect
            var newX = workspaceRect.topLeftX + xProportion * workspaceRect.width
            var newY = workspaceRect.topLeftY + yProportion * workspaceRect.height

            let windowWidth = windowRect.width
            let windowHeight = windowRect.height
            newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
            newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))

            setAxFrame(CGPoint(x: newX, y: newY), nil)
        }
        if isFullscreen {
            try await layoutFullscreen(context)
            isFullscreen = false
        }
    }

    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) async throws {
        let monitorRect = fullscreenWindowRect(self, in: context.workspace)
        let target = CGRect(origin: monitorRect.topLeftCorner, size: CGSize(width: monitorRect.width, height: monitorRect.height))
        if let window = self as? MacWindow, window.isHiddenInCorner {
            _ = try await window.restoreFromCorner(to: target)
        } else {
            setAxFrame(target.origin, target.size)
        }
    }
}

extension TilingContainer {
    @MainActor
    fileprivate func layoutTiles(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let rect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        let frames = tileChildFrames(in: rect, gaps: context.resolvedGaps)
        let selected = frameLayoutChildren
        if runtime.workspaceBackend.kind == .native {
            let total = selected.reduce(CGFloat.zero) { $0 + $1.getWeight(orientation) }
            let factor = total > 0 ? frames.reduce(CGFloat.zero) { $0 + $1.weight } / total : 1
            for child in children where !selected.contains(child) {
                child.setWeight(orientation, child.getWeight(orientation) * factor)
            }
        }
        if layout == .master, frames.count == 2, width > 0, height > 0 {
            masterRatio = frames[0].weight / rect.getDimension(orientation)
        }
        for (child, frame) in zip(selected, frames) {
            child.setWeight(orientation, frame.weight)
            let childVirtual = Rect(
                topLeftX: frame.virtual.topLeftX + virtual.topLeftX - point.x,
                topLeftY: frame.virtual.topLeftY + virtual.topLeftY - point.y,
                width: frame.virtual.width, height: frame.virtual.height)
            try await child.layoutRecursive(frame.physical.topLeftCorner,
                width: frame.physical.width, height: frame.physical.height, virtual: childVirtual, context)
        }
    }

    @MainActor
    fileprivate func layoutDwindle(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let rect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        let frames = dwindleChildFrames(in: rect, gaps: context.resolvedGaps)
        for (child, frame) in zip(frameLayoutChildren, frames) {
            let childVirtual = Rect(
                topLeftX: virtual.topLeftX + frame.topLeftX - point.x,
                topLeftY: virtual.topLeftY + frame.topLeftY - point.y,
                width: frame.width, height: frame.height,
            )
            try await child.layoutRecursive(frame.topLeftCorner, width: frame.width, height: frame.height, virtual: childVirtual, context)
        }
    }

    @MainActor
    fileprivate func layoutTabGroup(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        if usesWindowTabBehavior {
            let tabBarHeight = showsWindowTabs ? windowTabBarHeight : 0
            let shellHorizontalInset = showsWindowTabs ? windowTabGroupShellHorizontalInset() : 0
            let shellTopInset = showsWindowTabs ? windowTabGroupShellTopInset() : 0
            let shellBottomInset = showsWindowTabs ? windowTabGroupShellBottomInset() : 0
            let contentPoint = point + CGPoint(x: shellHorizontalInset, y: tabBarHeight + shellTopInset)
            let contentWidth = max(width - shellHorizontalInset * 2, 0)
            let contentHeight = max(height - tabBarHeight - shellTopInset - shellBottomInset, 0)
            let contentVirtual = Rect(
                topLeftX: virtual.topLeftX + shellHorizontalInset,
                topLeftY: virtual.topLeftY + tabBarHeight + shellTopInset,
                width: max(virtual.width - shellHorizontalInset * 2, 0),
                height: max(virtual.height - tabBarHeight - shellTopInset - shellBottomInset, 0),
            )
            guard let activeChild = mostRecentChild else { return }

            // Switch tabs by placing the newly active child first, then parking the old visible tabs.
            try await activeChild.layoutRecursive(
                contentPoint,
                width: contentWidth,
                height: contentHeight,
                virtual: contentVirtual,
                context,
            )
            for child in children where child != activeChild {
                if runtime.workspaceBackend.kind == .native {
                    // Native never parks windows: inactive tabs wait behind the active one.
                    try await child.layoutRecursive(contentPoint, width: contentWidth, height: contentHeight,
                        virtual: contentVirtual, context)
                } else {
                    try await child.hideTabbedWindows(context.workspace)
                }
            }
            return
        }

        guard let mruIndex: Int = mostRecentChild?.ownIndex else { return }
        for (index, child) in children.enumerated() {
            let extent = orientation == .h ? width : height
            let padding = min(CGFloat(max(config.tabGroupPadding, 0)), max(extent - 1, 0) / 2)
            let (lPadding, rPadding): (CGFloat, CGFloat) = switch index {
                case 0 where children.count == 1: (0, 0)
                case 0:                           (0, padding)
                case children.indices.last:       (padding, 0)
                case mruIndex - 1:                (0, 2 * padding)
                case mruIndex + 1:                (2 * padding, 0)
                default:                          (padding, padding)
            }
            switch orientation {
                case .h:
                    try await child.layoutRecursive(
                        point + CGPoint(x: lPadding, y: 0),
                        width: width - rPadding - lPadding,
                        height: height,
                        virtual: virtual,
                        context,
                    )
                case .v:
                    try await child.layoutRecursive(
                        point + CGPoint(x: 0, y: lPadding),
                        width: width,
                        height: height - lPadding - rPadding,
                        virtual: virtual,
                        context,
                    )
            }
        }
    }
}

@MainActor
func fitLayoutSizes(_ requested: [CGFloat], minimums: [CGFloat], total: CGFloat) -> [CGFloat] {
    TileLayoutGeometry.fit(requested, minimums: minimums, total: total)
}

@MainActor
extension TreeNode {
    func minimumLayoutExtent(along axis: Orientation, gaps: ResolvedGaps? = nil, rect: Rect? = nil) -> CGFloat {
        let gaps = gaps ?? ResolvedGaps(gaps: config.gaps, monitor: nodeMonitor ?? mainMonitor)
        switch nodeCases {
            case .window(let window):
                let minimum = window.minimumLayoutSize
                return axis == .h ? minimum.width : minimum.height
            case .tilingContainer(let container):
                let children = container.frameLayoutChildren
                let rect = rect ?? container.lastAppliedLayoutPhysicalRect ?? container.nodeMonitor?.visibleRectPaddedByOuterGaps
                if container.layout == .dwindle, let rect {
                    return container.dwindleMinimumExtent(children: children[...], along: axis, rect: rect, gaps: gaps)
                }
                let minimums = children.map { $0.minimumLayoutExtent(along: axis, gaps: gaps, rect: rect) }
                guard !minimums.isEmpty else { return 0 }
                if container.layout == .tabGroup || container.layout == .stacked {
                    if container.layout == .stacked {
                        return (minimums.max() ?? 0) + (container.orientation == axis && minimums.count > 1 ? CGFloat(max(config.tabGroupPadding, 0)) * 2 : 0)
                    }
                    let chrome = container.showsWindowTabs
                        ? (axis == .h ? 2 * windowTabGroupShellHorizontalInset()
                            : resolvedWindowTabBarHeight() + windowTabGroupShellTopInset() + windowTabGroupShellBottomInset()) : 0
                    return (minimums.max() ?? 0) + chrome
                }
                return container.orientation == axis
                    ? minimums.reduce(0, +) + CGFloat(gaps.inner.get(axis).toDouble()) * CGFloat(minimums.count - 1)
                    : minimums.max() ?? 0
            default: return 0
        }
    }
}

extension TreeNode {
    @MainActor
    fileprivate func hideTabbedWindows(_ workspace: Workspace) async throws {
        switch nodeCases {
            case .window(let window):
                window.lastAppliedLayoutPhysicalRect = nil
                window.lastAppliedLayoutVirtualRect = nil
                if let macWindow = window as? MacWindow {
                    try await macWindow.hideInCorner(.bottomRightCorner)
                }
            case .tilingContainer(let container):
                for child in container.children {
                    try await child.hideTabbedWindows(workspace)
                }
            case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return
        }
    }

    @MainActor
    fileprivate func hideAllWindowsExcept(_ targetWindow: Window) async throws {
        switch nodeCases {
            case .window(let window):
                guard window != targetWindow else { return }
                window.lastAppliedLayoutPhysicalRect = nil
                window.lastAppliedLayoutVirtualRect = nil
                if let macWindow = window as? MacWindow {
                    try await macWindow.hideInCorner(.bottomRightCorner)
                }
            case .tilingContainer(let container):
                for child in container.children {
                    try await child.hideAllWindowsExcept(targetWindow)
                }
            case .workspace(let workspace):
                for child in workspace.children {
                    try await child.hideAllWindowsExcept(targetWindow)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return
        }
    }

    @MainActor
    fileprivate func hideAllWindowsExcept(_ targetNode: TreeNode) async throws {
        if self === targetNode { return }
        switch nodeCases {
            case .window(let window):
                window.lastAppliedLayoutPhysicalRect = nil
                window.lastAppliedLayoutVirtualRect = nil
                if let macWindow = window as? MacWindow {
                    try await macWindow.hideInCorner(.bottomRightCorner)
                }
            case .tilingContainer(let container):
                for child in container.children {
                    try await child.hideAllWindowsExcept(targetNode)
                }
            case .workspace(let workspace):
                for child in workspace.children {
                    try await child.hideAllWindowsExcept(targetNode)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return
        }
    }
}
