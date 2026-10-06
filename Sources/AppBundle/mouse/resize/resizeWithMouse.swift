import AppKit
import Common

func resizedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let notif = notif as String
    let windowId = ax.containingWindowId()
    Task { @MainActor in
        if let windowId, WindowMotion.shared.isAnimating(windowId), NSEvent.pressedMouseButtons & 1 == 0 {
            Window.get(byId: windowId)?.invalidateLastKnownNativeState()
            return
        }
        WindowBorderController.shared.refresh()
        if WindowMouseInteractionOpacityController.shared.shouldSuppressObserverEvent(windowId: windowId) {
            return
        }
        if shouldIgnoreAxObserverEventForPostDragSuppression(windowId: windowId, notif: notif) {
            return
        }
        // See movedObs: geometry events invalidate the cached native state (consumers re-fetch
        // on demand), but suppressed events are our own moves whose authors maintain the cache.
        if let windowId {
            Window.get(byId: windowId)?.invalidateLastKnownNativeState()
        }
        guard RunSessionGuard.isServerEnabled != nil else { return }
        guard let windowId, let window = Window.get(byId: windowId) else {
            scheduleRefreshSession(.ax(notif))
            return
        }
        if isContinuingManagedDragSessionForResizedEvent(windowId) { return }
        guard try await isManipulatedWithMouse(window) else {
            scheduleRefreshSession(.ax(notif))
            return
        }
        guard window.parent is TilingContainer else {
            scheduleRefreshSession(.ax(notif))
            return
        }
        WindowMouseInteractionDriver.shared.startResize(windowId: window.windowId)
    }
}

@MainActor
func resetManipulatedWithMouseIfPossible() async throws {
    await WindowMouseInteractionDriver.shared.flushBeforeMouseUp()
    let didApplyPendingDragIntent = applyPendingWindowDragIntentIfPossible()
    clearPendingWindowDragIntent()
    if currentlyManipulatedWithMouseWindowId != nil || didApplyPendingDragIntent {
        armGlobalPostDragAxObserverSuppression()
        cancelManipulatedWithMouseState()
        scheduleRefreshSession(.resetManipulatedWithMouse, optimisticallyPreLayoutWorkspaces: true)
    }
    WindowMouseInteractionDriver.shared.stop()
}

private let adaptiveWeightBeforeResizeWithMouseKey = TreeNodeUserDataKey<CGFloat>(key: "adaptiveWeightBeforeResizeWithMouseKey")

@MainActor
func updateCompositedResizePreview(_ window: Window, rect: Rect) {
    syncClosedWindowsCacheToCurrentWorld()
    // The actively resized content stays real. Hide all tab chrome, including the active
    // group, so every inactive group can be represented by one uninterrupted glass pane.
    WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: false)
    guard let workspace = window.nodeWorkspace,
          workspace.isVisible,
          let weightMap = proposedResizeWeightMap(window, rect: rect)
    else {
        logWindowDragLive("resizePreview hide requested reason=resizePreview.no-workspace-or-weightMap window=\(window.windowId) workspace=\(window.nodeWorkspace?.name.description ?? "nil") visible=\(window.nodeWorkspace?.isVisible.description ?? "nil") hasWeightMap=\(proposedResizeWeightMap(window, rect: rect) != nil)")
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "resizePreview.no-workspace-or-weightMap")
        return
    }
    WindowResizePreviewPanel.shared.beginStableFrame(workspace.workspaceMonitor.rect.toAppKitScreenRect)
    let items = windowResizePreviewItems(
        in: workspace,
        weightMap: weightMap,
        excludingActiveWindowId: window.windowId,
    )
    guard !items.isEmpty else {
        logWindowDragLive("resizePreview hide requested reason=resizePreview.no-items window=\(window.windowId)")
        WindowTabStripPanelController.shared.clearHiddenPassiveTabGroupChrome()
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "resizePreview.no-items")
        return
    }
    currentlyManipulatedWithMouseWindowId = window.windowId
    setCurrentMouseManipulationKind(.resize)
    WindowResizePreviewPanel.shared.show(items, presentation: .resizeOverlay)
}

@MainActor
func applyResizeWithMouse(_ window: Window, rect: Rect) {
    syncClosedWindowsCacheToCurrentWorld()
    guard let weightMap = proposedResizeWeightMap(window, rect: rect) else { return }
    for change in weightMap.changes {
        change.node.setWeight(change.orientation, change.weight)
    }
    for change in weightMap.dwindleChanges {
        change.container.setDwindleSplitRatio(change.ratio, at: change.index)
    }
    currentlyManipulatedWithMouseWindowId = window.windowId
    setCurrentMouseManipulationKind(.resize)
    clearPendingWindowDragIntent()
}

struct WindowResizeWeightChange {
    let node: TreeNode
    let orientation: Orientation
    let weight: CGFloat
}

struct WindowResizePreviewWeightMap {
    struct DwindleChange {
        let container: TilingContainer
        let index: Int
        let ratio: CGFloat
    }
    private(set) var dwindleChanges: [DwindleChange] = []

    mutating func setDwindleRatio(_ ratio: CGFloat, for container: TilingContainer, at index: Int) {
        dwindleChanges.removeAll { $0.container === container && $0.index == index }
        dwindleChanges.append(DwindleChange(container: container, index: index, ratio: ratio))
    }

    func dwindleRatio(for container: TilingContainer, at index: Int) -> CGFloat {
        dwindleChanges.first { $0.container === container && $0.index == index }?.ratio ?? container.dwindleSplitRatio(at: index)
    }
    private var weights: [WindowResizeWeightKey: CGFloat] = [:]
    private var nodes: [ObjectIdentifier: TreeNode] = [:]

    @MainActor
    var changes: [WindowResizeWeightChange] {
        weights.compactMap { key, weight in
            guard let node = nodes[key.nodeId] else { return nil }
            return WindowResizeWeightChange(node: node, orientation: key.orientation, weight: weight)
        }
    }

    mutating func set(_ weight: CGFloat, for node: TreeNode, orientation: Orientation) {
        let nodeId = ObjectIdentifier(node)
        weights[WindowResizeWeightKey(nodeId: nodeId, orientation: orientation)] = weight
        nodes[nodeId] = node
    }

    @MainActor
    func weight(for node: TreeNode, orientation: Orientation) -> CGFloat {
        weights[WindowResizeWeightKey(nodeId: ObjectIdentifier(node), orientation: orientation)] ??
            node.getWeight(orientation)
    }
}

private struct WindowResizeWeightKey: Hashable {
    let nodeId: ObjectIdentifier
    let orientation: Orientation
}

@MainActor
func proposedResizeWeightMap(_ window: Window, rect: Rect) -> WindowResizePreviewWeightMap? {
    guard window.parent is TilingContainer else { return nil }
    guard let lastAppliedLayoutRect = window.lastAppliedLayoutPhysicalRect else { return nil }
    var weightMap = WindowResizePreviewWeightMap()
    if let workspace = window.nodeWorkspace {
        // Recompute after each axis, so an automatic split that changes shape is never
        // resized using the other axis's stale length. Adjacency is checked at mouse-down.
        let originalTargets = window.parentsWithSelf.flatMap { $0.dwindleResizeTargets() }
        for axis in [Orientation.h, .v] {
            for node in window.parentsWithSelf.reversed() {
                let geometry = dwindleGeometry(in: workspace, weightMap: weightMap, physical: true)
                for split in node.dwindleResizeTargets(geometry: geometry) where split.orientation == axis {
                    guard let original = originalTargets.first(where: {
                        $0.container === split.container && $0.splitIndex == split.splitIndex && $0.orientation == axis
                    }) else { continue }
                    let oldEdge: CGFloat
                    let newEdge: CGFloat
                    switch (axis, split.resizesLeadingChild) {
                        case (.h, true): (oldEdge, newEdge) = (lastAppliedLayoutRect.maxX, rect.maxX)
                        case (.h, false): (oldEdge, newEdge) = (lastAppliedLayoutRect.minX, rect.minX)
                        case (.v, true): (oldEdge, newEdge) = (lastAppliedLayoutRect.maxY, rect.maxY)
                        case (.v, false): (oldEdge, newEdge) = (lastAppliedLayoutRect.minY, rect.minY)
                    }
                    guard abs(oldEdge - original.resizeEdge) < 1, abs(newEdge - oldEdge) > 5 else { continue }
                    let current = split.resizesLeadingChild ? split.leadingLength : split.availableLength - split.leadingLength
                    let delta = (newEdge - oldEdge) * (split.resizesLeadingChild ? 1 : -1)
                    weightMap.setDwindleRatio(split.ratio(forLength: current + delta), for: split.container, at: split.splitIndex)
                }
            }
        }
    }
    let (lParent, lOwnIndex) = window.closestParent(hasChildrenInDirection: .left, withLayout: .tiles) ?? (nil, nil)
    let (dParent, dOwnIndex) = window.closestParent(hasChildrenInDirection: .down, withLayout: .tiles) ?? (nil, nil)
    let (uParent, uOwnIndex) = window.closestParent(hasChildrenInDirection: .up, withLayout: .tiles) ?? (nil, nil)
    let (rParent, rOwnIndex) = window.closestParent(hasChildrenInDirection: .right, withLayout: .tiles) ?? (nil, nil)
    let table: [(CGFloat, TilingContainer?, Int?, Int?)] = [
        (lastAppliedLayoutRect.minX - rect.minX, lParent, 0,                        lOwnIndex),               // Horizontal, to the left of the window
        (rect.maxY - lastAppliedLayoutRect.maxY, dParent, dOwnIndex.map { $0 + 1 }, dParent?.children.count), // Vertical, to the down of the window
        (lastAppliedLayoutRect.minY - rect.minY, uParent, 0,                        uOwnIndex),               // Vertical, to the up of the window
        (rect.maxX - lastAppliedLayoutRect.maxX, rParent, rOwnIndex.map { $0 + 1 }, rParent?.children.count), // Horizontal, to the right of the window
    ]
    for (diff, parent, startIndex, pastTheEndIndex) in table {
        if let parent, let startIndex, let pastTheEndIndex, pastTheEndIndex - startIndex > 0 && abs(diff) > 5 { // 5 pixels should be enough to fight with accumulated floating precision error
            let orientation = parent.orientation
            let resizedNodes = Array(window.parentsWithSelf.lazy
                .prefix(while: { $0 != parent })
                .filter {
                    let parent = $0.parent as? TilingContainer
                    return parent?.orientation == orientation && parent?.layout == .tiles
                })
            let siblings = Array(parent.children[startIndex ..< pastTheEndIndex])
            let siblingMultiplier = -CGFloat(1).div(siblings.count).orDie()
            let constrainedDiff = constrainedTiledResizeDiff(
                diff,
                adjustments: resizedNodes.map {
                    TiledResizeAdjustment(weight: $0.getWeightBeforeResize(orientation), multiplier: 1)
                } + siblings.map {
                    TiledResizeAdjustment(weight: $0.getWeightBeforeResize(orientation), multiplier: siblingMultiplier)
                },
            )
            let siblingDiff = constrainedDiff.div(siblings.count).orDie()

            for node in resizedNodes {
                weightMap.set(node.getWeightBeforeResize(orientation) + constrainedDiff, for: node, orientation: orientation)
            }
            for sibling in siblings {
                weightMap.set(sibling.getWeightBeforeResize(orientation) - siblingDiff, for: sibling, orientation: orientation)
            }
        }
    }
    return weightMap
}

extension TreeNode {
    @MainActor
    func getWeightBeforeResize(_ orientation: Orientation) -> CGFloat {
        let currentWeight = getWeight(orientation) // Check assertions
        return getUserData(key: adaptiveWeightBeforeResizeWithMouseKey)
            ?? (lastAppliedLayoutVirtualRect?.getDimension(orientation) ?? currentWeight)
            .also { putUserData(key: adaptiveWeightBeforeResizeWithMouseKey, data: $0) }
    }

    func resetResizeWeightBeforeResizeRecursive() {
        cleanUserData(key: adaptiveWeightBeforeResizeWithMouseKey)
        for child in children {
            child.resetResizeWeightBeforeResizeRecursive()
        }
    }
}
