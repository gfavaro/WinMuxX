import AppKit
import Common

extension Workspace {
    @MainActor
    func layoutWorkspace() async throws {
        if isEffectivelyEmpty { return }
        let rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        let context = LayoutContext(self)
        if let tabGroup = rootTilingContainer.allTabbedContainersRecursive.first(where: \.hasFullscreenTab) {
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
            lastAppliedLayoutPhysicalRect = rect
            lastAppliedLayoutVirtualRect = rect
            rootTilingContainer.lastAppliedLayoutPhysicalRect = rect
            rootTilingContainer.lastAppliedLayoutVirtualRect = rect
            try await hideAllWindowsExcept(fullscreenWindow)
            fullscreenWindow.lastAppliedLayoutVirtualRect = rect
            fullscreenWindow.lastAppliedLayoutPhysicalRect = nil
            fullscreenWindow.layoutFullscreen(context)
            return
        }
        // If monitors are aligned vertically and the monitor below has smaller width, then macOS may not allow the
        // window on the upper monitor to take full width. rect.height - 1 resolves this problem
        // But I also faced this problem in monitors horizontal configuration. ¯\_(ツ)_/¯
        try await layoutRecursive(rect.topLeftCorner, width: rect.width, height: rect.height - 1, virtual: rect, context)
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
                if window.windowId != currentlyManipulatedWithMouseWindowId || isPinnedDraggedWindow(window.windowId) {
                    let previousPhysicalRect = lastAppliedLayoutPhysicalRect
                    lastAppliedLayoutVirtualRect = virtual
                    let isFullscreenTab = window.nearestWindowTabGroup?.hasFullscreenTab == true
                    if window.isFullscreen && !isFullscreenTab && window == context.workspace.rootTilingContainer.mostRecentWindowRecursive {
                        lastAppliedLayoutPhysicalRect = nil
                        window.layoutFullscreen(context)
                    } else {
                        lastAppliedLayoutPhysicalRect = physicalRect
                        if !isFullscreenTab {
                            window.isFullscreen = false
                        }
                        if !canReuseLastAppliedWindowFrame(previousPhysicalRect: previousPhysicalRect, nextPhysicalRect: physicalRect) {
                            WindowMotion.shared.apply(window, target: CGRect(origin: point, size: CGSize(width: width, height: height)))
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
                    case .tiles:
                        try await container.layoutTiles(point, width: width, height: height, virtual: virtual, context)
                    case .dwindle:
                        try await container.layoutDwindle(point, width: width, height: height, virtual: virtual, context)
                    case .tabGroup:
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
    return previousPhysicalRect.topLeftX == nextPhysicalRect.topLeftX &&
        previousPhysicalRect.topLeftY == nextPhysicalRect.topLeftY &&
        previousPhysicalRect.width == nextPhysicalRect.width &&
        previousPhysicalRect.height == nextPhysicalRect.height
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
        // With a single monitor the cross-monitor proportional move below is always a no-op,
        // so skip the AX round-trip it would need. This runs for every floating window on
        // every layout pass.
        if monitors.count == 1 {
            if isFullscreen {
                layoutFullscreen(context)
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
            layoutFullscreen(context)
            isFullscreen = false
        }
    }

    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let monitorRect = noOuterGapsInFullscreen
            ? context.workspace.workspaceMonitor.visibleRect
            : context.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        setAxFrame(monitorRect.topLeftCorner, CGSize(width: monitorRect.width, height: monitorRect.height))
    }
}

extension TilingContainer {
    @MainActor
    fileprivate func layoutTiles(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let rect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        let frames = tileChildFrames(in: rect, gaps: context.resolvedGaps)
        for (child, frame) in zip(children, frames) {
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
        for (child, frame) in zip(children, frames) {
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
                try await child.hideTabbedWindows(context.workspace)
            }
            return
        }

        guard let mruIndex: Int = mostRecentChild?.ownIndex else { return }
        for (index, child) in children.enumerated() {
            let padding = CGFloat(config.tabGroupPadding)
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
    guard requested.count == minimums.count,
          !requested.isEmpty,
          minimums.allSatisfy({ $0.isFinite && $0 >= 0 }),
          requested.allSatisfy({ $0.isFinite && $0 >= 0 }),
          minimums.reduce(0, +) <= total else { return requested }
    var result = requested
    var pinned = Set<Int>()
    while let short = result.indices.first(where: { !pinned.contains($0) && result[$0] + 0.5 < minimums[$0] }) {
        pinned.insert(short)
        let pinnedTotal = pinned.reduce(CGFloat.zero) { $0 + minimums[$1] }
        let free = result.indices.filter { !pinned.contains($0) }
        let freeRequested = free.reduce(CGFloat.zero) { $0 + requested[$1] }
        for index in pinned { result[index] = minimums[index] }
        let remaining = max(total - pinnedTotal, 0)
        for index in free {
            result[index] = freeRequested > 0 ? remaining * requested[index] / freeRequested : remaining / CGFloat(max(free.count, 1))
        }
    }
    return result
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
                let rect = rect ?? container.lastAppliedLayoutPhysicalRect ?? container.nodeMonitor?.visibleRectPaddedByOuterGaps
                if container.layout == .dwindle, let rect {
                    return container.dwindleMinimumExtent(children: container.children[...], along: axis, rect: rect, gaps: gaps)
                }
                let minimums = container.children.map { $0.minimumLayoutExtent(along: axis, gaps: gaps, rect: rect) }
                guard !minimums.isEmpty else { return 0 }
                if container.layout == .tabGroup {
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
