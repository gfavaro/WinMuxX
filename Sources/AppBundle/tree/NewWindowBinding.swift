import AppKit
import Common

@MainActor
func unbindAndGetBindingDataForNewWindow(_ windowId: UInt32, _ macApp: MacApp, _ workspace: Workspace, window: Window?,
                                          newlyOpened: Bool = false) async throws -> BindingData {
    let parent = window?.parent
    let windowLevel = getWindowLevel(for: windowId)
    let type = try await macApp.getAxUiElementWindowType(windowId, windowLevel)
    try checkCancellation()
    if let window {
        guard window.parent === parent, Window.get(byId: windowId) === window else { throw CancellationError() }
    }
    return bindingDataForNewWindow(type: type, workspace: workspace, window: window,
        newlyOpenedBundleId: newlyOpened ? .some(macApp.rawAppBundleId) : nil)
}

@MainActor
/// `newlyOpenedBundleId` is set only for a window that just opened (its app's bundle ID, which
/// may itself be nil). Explicit moves and tiling commands leave it nil and are never redirected.
func bindingDataForNewWindow(type: AxUiElementWindowType, workspace: Workspace, window: Window?,
                             newlyOpenedBundleId: String?? = nil) -> BindingData {
    switch type {
        case .popup: BindingData(parent: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .dialog: BindingData(parent: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .window: bindingDataForNewRegularWindow(workspace, window: window, newlyOpenedBundleId: newlyOpenedBundleId)
    }
}

@MainActor
func bindingDataForNewRegularWindow(_ workspace: Workspace, window: Window?, newlyOpenedBundleId: String?? = nil) -> BindingData {
    guard config.automaticallyTileNewWindows else {
        window?.unbindFromParent()
        return BindingData(parent: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    return bindingDataForNewTilingWindow(workspace, window: window, newlyOpenedBundleId: newlyOpenedBundleId)
}

@MainActor
func bindingDataForNewTilingWindow(_ workspace: Workspace, window: Window?, newlyOpenedBundleId: String?? = nil) -> BindingData {
    window?.unbindFromParent()
    if let tabGroupBinding = autoAddNewWindowToFocusedTabGroupBinding(workspace) {
        return tabGroupBinding
    }
    if workspace.arrangement == .master {
        let root = workspace.arrangementGroupParent !== workspace.rootTilingContainer
            ? workspace.arrangementGroupParent : ensureRootSupportsColumns(workspace)
        let focused = focus.windowOrNil?.topLevelWorkspaceGroup
        let index = focused.flatMap { root.children.firstIndex(of: $0) }.map { $0 + 1 } ?? root.children.count
        return BindingData(parent: root, adaptiveWeight: WEIGHT_AUTO, index: index)
    }
    guard let mruWindow = workspace.mostRecentWindowRecursive,
          let tilingParent = mruWindow.parent as? TilingContainer
    else {
        return BindingData(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    if workspace.rootTilingContainer.layout == .dwindle {
        workspace.materializeDwindleTree()
        if let newBundleId = newlyOpenedBundleId,
           let joined = tabGroupBindingInsteadOfSqueezing(workspace: workspace, anchorWindow: mruWindow, newBundleId: newBundleId) {
            return joined
        }
        return bindingDataBySplittingDwindleAnchor(workspace: workspace, focusedWindow: mruWindow)
    }
    if tilingParent.layout == .tabGroup {
        return bindingDataAfterTabGroup(workspace: workspace, tabGroup: tilingParent)
    }
    return BindingData(parent: tilingParent, adaptiveWeight: WEIGHT_AUTO, index: mruWindow.ownIndex.orDie() + 1)
}

@MainActor
private func bindingDataBySplittingDwindleAnchor(workspace: Workspace, focusedWindow: Window) -> BindingData {
    var anchor: TreeNode = focusedWindow
    while let parent = anchor.parent as? TilingContainer, parent.layout == .tabGroup {
        anchor = parent
    }
    let splitRect = anchor.lastAppliedLayoutPhysicalRect ?? anchor.lastAppliedLayoutVirtualRect ?? workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    let orientation: Orientation = splitRect.width >= splitRect.height ? .h : .v
    let parent = anchor.parent as? TilingContainer
    if let parent, parent.layout == .dwindle, parent.isExplicitDwindle,
       parent.navigationOrientation == orientation || parent.children.count == 1 {
        if parent.children.count == 1 { parent.dwindleOrientation = orientation }
        return BindingData(parent: parent, adaptiveWeight: WEIGHT_AUTO, index: anchor.ownIndex.orDie() + 1)
    }
    if let parent, parent.layout == .tiles, parent.orientation == orientation {
        return BindingData(parent: parent, adaptiveWeight: WEIGHT_AUTO, index: anchor.ownIndex.orDie() + 1)
    }
    let ratios = parent?.dwindleSplitRatios
    let siblingRatios = parent?.dwindleChildRatios
    let previousBinding = anchor.unbindFromParent()
    let split = TilingContainer(
        parent: previousBinding.parent,
        adaptiveWeight: previousBinding.adaptiveWeight,
        orientation,
        .dwindle,
        index: previousBinding.index,
    )
    if let ratios { parent?.dwindleSplitRatios = ratios }
    if let siblingRatios { parent?.dwindleChildRatios = siblingRatios }
    split.dwindleOrientation = orientation
    split.dwindleChildRatios = []
    anchor.bind(to: split, adaptiveWeight: 1, index: 0)
    return BindingData(parent: split, adaptiveWeight: 1, index: 1)
}

@MainActor
private func autoAddNewWindowToFocusedTabGroupBinding(_ workspace: Workspace) -> BindingData? {
    guard config.autoAddNewWindowsToTabGroup,
          let focusedWindow = focus.windowOrNil,
          focusedWindow.nodeWorkspace == workspace,
          let tabGroup = focusedWindow.parent as? TilingContainer,
          tabGroup.layout == .tabGroup
    else { return nil }
    return BindingData(parent: tabGroup, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
}

@MainActor
private func bindingDataAfterTabGroup(workspace: Workspace, tabGroup: TilingContainer) -> BindingData {
    var insertionAnchor: TreeNode = tabGroup
    var insertionParent: NonLeafTreeNodeObject = tabGroup.parent.orDie()
    while let parent = insertionParent as? TilingContainer, parent.layout == .tabGroup {
        insertionAnchor = parent
        insertionParent = parent.parent.orDie()
    }
    switch insertionParent.cases {
        case .tilingContainer(let parent):
            return BindingData(parent: parent, adaptiveWeight: WEIGHT_AUTO, index: insertionAnchor.ownIndex.orDie() + 1)
        case .workspace:
            ensureTabGroupAnchorHasWorkspaceRootContainer(workspace: workspace, insertionAnchor: insertionAnchor, tabGroup: tabGroup)
            return BindingData(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer:
            die("Impossible insertion parent for tiling window")
    }
}

@MainActor
private func ensureTabGroupAnchorHasWorkspaceRootContainer(
    workspace: Workspace,
    insertionAnchor: TreeNode,
    tabGroup: TilingContainer,
) {
    let previousRoot = workspace.rootTilingContainer
    guard previousRoot === insertionAnchor else { return }
    previousRoot.unbindFromParent()
    _ = TilingContainer(parent: workspace, adaptiveWeight: WEIGHT_AUTO, tabGroup.orientation.opposite, .tiles, index: 0)
    previousRoot.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
}

/// Whether halving a tile of `size` along its longer side, as Dwindle does for a new window,
/// leaves a half smaller than one of these minimum extents along that side.
func newWindowSplitWouldSqueeze(tile size: CGSize, gap: CGSize, minimumExtents: [CGFloat]) -> Bool {
    let horizontal = size.width >= size.height
    let half = (horizontal ? size.width - gap.width : size.height - gap.height) / 2
    return minimumExtents.contains { $0 > half }
}

/// A new window joins the tile's tab group, starting one when needed, instead of splitting a
/// tile into halves smaller than either app's learned minimum size.
@MainActor
private func tabGroupBindingInsteadOfSqueezing(workspace: Workspace, anchorWindow: Window, newBundleId: String?) -> BindingData? {
    var anchor: TreeNode = anchorWindow
    while let parent = anchor.parent as? TilingContainer, parent.layout == .tabGroup { anchor = parent }
    guard let splitRect = anchor.lastAppliedLayoutPhysicalRect ?? anchor.lastAppliedLayoutVirtualRect else { return nil }
    let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    let gap = CGSize(width: CGFloat(gaps.inner.horizontal.toDouble()), height: CGFloat(gaps.inner.vertical.toDouble()))
    let horizontal = splitRect.width >= splitRect.height
    // The tile's whole minimum: every tab of a group, not only the one in front, plus its chrome.
    let tileMinimum = anchor.minimumLayoutExtent(along: horizontal ? .h : .v, gaps: gaps, rect: splitRect)
    let newMinimum = PersistedAppMinimums.shared.size(for: newBundleId).map { horizontal ? $0.width : $0.height } ?? 0
    guard newWindowSplitWouldSqueeze(tile: CGSize(width: splitRect.width, height: splitRect.height), gap: gap,
        minimumExtents: [tileMinimum, newMinimum]) else { return nil }
    if let group = anchorWindow.parent as? TilingContainer, group.layout == .tabGroup {
        return BindingData(parent: group, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    // Keep the surrounding Dwindle split exactly as it was, as splitting an anchor does.
    let parent = anchorWindow.parent as? TilingContainer
    let ratios = parent?.dwindleSplitRatios
    let siblingRatios = parent?.dwindleChildRatios
    let binding = anchorWindow.unbindFromParent()
    let group = TilingContainer(parent: binding.parent, adaptiveWeight: binding.adaptiveWeight,
        (binding.parent as? TilingContainer)?.orientation.opposite ?? .h, .tabGroup, index: binding.index)
    if let ratios { parent?.dwindleSplitRatios = ratios }
    if let siblingRatios { parent?.dwindleChildRatios = siblingRatios }
    anchorWindow.bind(to: group, adaptiveWeight: WEIGHT_AUTO, index: 0)
    return BindingData(parent: group, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
}
