import AppKit
import Common

/// Tabs are one spatial target; tab-index/tab-next/tab-prev select their hidden content.
@MainActor
func dwindleGeometry(in workspace: Workspace, weightMap: WindowResizePreviewWeightMap = .init(), physical: Bool = false) -> [ObjectIdentifier: Rect] {
    var result: [ObjectIdentifier: Rect] = [:]
    let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    func visit(_ node: TreeNode, _ rect: Rect) {
        result[ObjectIdentifier(node)] = rect
        if node is Window { return }
        guard let container = node as? TilingContainer else { return }
        switch container.layout {
            case .tabGroup:
                if let active = container.mostRecentChild {
                    let content = physical && container.showsWindowTabs
                        ? Rect(topLeftX: rect.topLeftX + windowTabGroupShellHorizontalInset(),
                            topLeftY: rect.topLeftY + resolvedWindowTabBarHeight() + windowTabGroupShellTopInset(),
                            width: max(rect.width - 2 * windowTabGroupShellHorizontalInset(), 0),
                            height: max(rect.height - resolvedWindowTabBarHeight() - windowTabGroupShellTopInset() - windowTabGroupShellBottomInset(), 0)) : rect
                    visit(active, content)
                }
            case .dwindle:
                let frames = container.dwindleChildFrames(in: rect, gaps: gaps, ratioAt: { weightMap.dwindleRatio(for: container, at: $0) }, enforceMinimums: physical)
                for (child, frame) in zip(container.children, frames) { visit(child, frame) }
            case .tiles:
                let frames = container.tileChildFrames(in: rect, gaps: gaps) {
                    weightMap.weight(for: $0, orientation: container.orientation)
                }
                for (child, frame) in zip(container.children, frames) {
                    visit(child, physical ? frame.physical : frame.virtual)
                }
        }
    }
    let rect = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    visit(workspace.rootTilingContainer, physical ? rect.copy(\.height, max(rect.height - 1, 0)) : rect)
    return result
}
