import AppKit
import Common

/// Workspace-wide master policy. It changes only arrangement state; the tree
/// below each top-level group remains user-owned and untouched.
extension Workspace {
    @MainActor
    func transitionArrangement(to next: WorkspaceLayoutName, focused: Window? = nil) {
        ScrollingWindowOrdering.shared.cancel()
        WorkspaceScrollingGestureController.shared.cancelForWorkspaceChange(self)
        for window in allLeafWindowsRecursive { window.isConcealedByScrolling = false }
        if next != .dwindle { preserveAtomicRootAsArrangementGroup() }
        arrangement = next
        if next == .master, let focused,
           let index = workspaceLayoutUnits.firstIndex(where: { $0 === focused.topLevelWorkspaceGroup }) {
            masterGroupIndex = index
        }
    }

    @MainActor
    private func preserveAtomicRootAsArrangementGroup() {
        let previousRoot = rootTilingContainer
        guard previousRoot.layout == .tabGroup || previousRoot.layout == .stacked else { return }
        let orientation = previousRoot.orientation
        previousRoot.unbindFromParent()
        let outer = TilingContainer(parent: self, adaptiveWeight: WEIGHT_AUTO, orientation, .tiles, index: 0)
        previousRoot.bind(to: outer, adaptiveWeight: WEIGHT_AUTO, index: 0)
    }

    @MainActor
    var usesSpatialFocus: Bool {
        arrangement != .dwindle || rootTilingContainer.layout == .dwindle || rootTilingContainer.layout == .master
    }

    @MainActor
    func configureMasterLayout(focused window: Window?) {
        transitionArrangement(to: .master, focused: window)
        if let window, let index = workspaceLayoutUnits.firstIndex(where: { $0 === window.topLevelWorkspaceGroup }) {
            masterGroupIndex = index
        }
    }

    @MainActor
    func normalizeMasterLayout() {
        guard arrangement == .master else { return }
        masterGroupIndex = min(max(masterGroupIndex, 0), max(workspaceLayoutUnits.count - 1, 0))
    }

    @MainActor
    func resizeMasterPane(_ window: Window, dimension: ResizeCmdArgs.Dimension, units: ResizeCmdArgs.Units) -> Bool {
        guard arrangement == .master, workspaceLayoutUnits.count > 1 else { return false }
        let axis = config.master.side.orientation
        let requestedAxis: Orientation = switch dimension {
            case .width: .h
            case .height: .v
            case .smart: axis
            case .smartOpposite: axis.opposite
        }
        guard requestedAxis == axis else { return false }
        let rect = workspaceTilingRect(self)
        let extent = rect.getDimension(axis)
        guard extent > 0,
              let frame = arrangementGroupFrames(in: rect, gaps: ResolvedGaps(gaps: config.gaps, monitor: workspaceMonitor))
                .first(where: { $0.node === window.topLevelWorkspaceGroup }) else { return false }
        let current = frame.physical.getDimension(axis)
        let delta: CGFloat = switch units {
            case .set(let value): CGFloat(value) - current
            case .add(let value): CGFloat(value)
            case .subtract(let value): -CGFloat(value)
        }
        let isPrimary = workspaceLayoutUnits[masterGroupIndex] === frame.node
        let ratio = masterRatio ?? CGFloat(config.master.size)
        masterRatio = min(max(ratio + (isPrimary ? delta : -delta) / extent, 0.1), 0.9)
        return true
    }

    @MainActor
    func changeMasterStackLayout(between layouts: [Layout]) -> Bool {
        // Stack presentation is a workspace policy. The nested layout of each
        // member group is never rewritten.
        guard !layouts.isEmpty, layouts.allSatisfy({ $0 == .tiles || $0 == .stacked }) else { return false }
        let current = masterStackLayout
        let target = nextLayout(in: layouts, matching: { $0 == current })
        guard target != current else { return false }
        masterStackLayout = target
        return true
    }

    @MainActor
    @discardableResult
    func promoteToMaster(_ window: Window) -> Bool {
        guard arrangement == .master,
              let index = workspaceLayoutUnits.firstIndex(where: { $0 === window.topLevelWorkspaceGroup }),
              workspaceLayoutUnits.indices.contains(index) else { return false }
        masterGroupIndex = index
        return true
    }
}

extension TreeNode {
    @MainActor
    var topLevelWorkspaceGroup: TreeNode {
        if let workspace = nodeWorkspace,
           workspace.rootTilingContainer.layout == .tabGroup || workspace.rootTilingContainer.layout == .stacked {
            return workspace.rootTilingContainer
        }
        var node: TreeNode = self
        while let parent = node.parent as? TilingContainer, !(parent.parent is Workspace) {
            node = parent
        }
        return node
    }
}

extension Workspace {
    @MainActor
    var workspaceLayoutUnits: [TreeNode] {
        let root = rootTilingContainer
        return root.layout == .tabGroup || root.layout == .stacked ? [root] : root.children
    }
}
