import AppKit
import Common

/// The tabs of a Tabbed workspace: each window on its own, except windows in a side-by-side
/// split, which share one tab. Nested tab groups and ordinary splits contribute each window.
extension Workspace {
    @MainActor var tabbedUnits: [TreeNode] { tabbedUnits(of: rootTilingContainer) }

    @MainActor private func tabbedUnits(of node: TreeNode) -> [TreeNode] {
        switch node.nodeCases {
            case .window: return [node]
            case .tilingContainer(let container):
                // Kept as one tab while it holds several windows, even through a nested split.
                if container.isTabbedSplit, container.allLeafWindowsRecursive.count > 1 { return [container] }
                return container.children.flatMap(tabbedUnits(of:))
            default: return []
        }
    }

    /// The tab shown: the one holding the most recently focused tiled window.
    @MainActor var tabbedActiveUnit: TreeNode? {
        guard let window = rootTilingContainer.mostRecentWindowRecursive else { return nil }
        return tabbedUnit(containing: window)
    }

    @MainActor func tabbedUnit(containing window: Window) -> TreeNode? {
        tabbedUnits.first { $0 === window || ($0 as? TilingContainer)?.allLeafWindowsRecursive.contains(where: { $0 === window }) == true }
    }
}

extension TreeNode {
    /// The window a tab shows first and its bar entry stands for.
    @MainActor var tabbedRepresentative: Window? {
        (self as? Window) ?? mostRecentWindowRecursive
    }
}

/// Moves the tab holding `window` beside the tab shown, so both show side by side as one tab.
/// A tab that is already side by side gains the window. Returns false when nothing changes.
@MainActor
func showTabbedTabBesideCurrent(_ window: Window) -> Bool {
    guard let workspace = window.nodeWorkspace, workspace.arrangement == .tabbed,
          let shown = workspace.tabbedActiveUnit, let moving = workspace.tabbedUnit(containing: window),
          moving !== shown else { return false }
    // An incoming side-by-side tab nests whole, keeping its own layout; splitting the combined
    // tab later makes it a tab of its own again.
    moving.unbindFromParent()
    let split: TilingContainer
    if let existing = shown as? TilingContainer {
        split = existing
    } else {
        let parent = shown.parent as? TilingContainer
        let ratios = parent?.dwindleSplitRatios, siblingRatios = parent?.dwindleChildRatios
        let binding = shown.unbindFromParent()
        split = TilingContainer(parent: binding.parent, adaptiveWeight: binding.adaptiveWeight, .h, .tiles, index: binding.index)
        if let ratios { parent?.dwindleSplitRatios = ratios }
        if let siblingRatios { parent?.dwindleChildRatios = siblingRatios }
        split.isTabbedSplit = true
        shown.bind(to: split, adaptiveWeight: WEIGHT_AUTO, index: 0)
    }
    moving.bind(to: split, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    window.markAsMostRecentChild()
    return true
}

/// Turns a side-by-side tab back into one tab per window. The windows keep their places, so in
/// Dwindle or Master they stay side by side.
@MainActor
func splitTabbedTabIntoTabs(_ window: Window) -> Bool {
    guard let workspace = window.nodeWorkspace, workspace.arrangement == .tabbed,
          let split = workspace.tabbedUnit(containing: window) as? TilingContainer, split.isTabbedSplit else { return false }
    split.isTabbedSplit = false
    return true
}
