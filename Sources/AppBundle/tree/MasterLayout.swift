import AppKit
import Common

/// Workspace-wide master policy. It changes only arrangement state; the tree
/// below each top-level group remains user-owned and untouched.
extension Workspace {
    @MainActor
    func transitionArrangement(to next: WorkspaceLayoutName, focused: Window? = nil) {
        if next != .dwindle { preserveAtomicRootAsArrangementGroup() }
        let entering = arrangement != next
        arrangement = next
        if next == .tabbed {
            syncTabbedGroups()
            // Switching to Tabbed starts from the window being worked in. Restoring a workspace
            // that already was Tabbed keeps each group's saved tab.
            if entering { rootTilingContainer.mostRecentWindowRecursive?.noteTabbedFocus() }
        }
        if next == .master, let focused,
           let index = workspaceLayoutUnits.firstIndex(where: { $0 === focused.topLevelWorkspaceGroup }) {
            masterGroupIndex = index
        }
    }

    @MainActor
    private func preserveAtomicRootAsArrangementGroup() {
        let previousRoot = rootTilingContainer
        guard previousRoot.layout == .tabGroup else { return }
        let orientation = previousRoot.orientation
        previousRoot.unbindFromParent()
        let outer = TilingContainer(parent: self, adaptiveWeight: WEIGHT_AUTO, orientation, .tiles, index: 0)
        previousRoot.bind(to: outer, adaptiveWeight: WEIGHT_AUTO, index: 0)
    }

    @MainActor
    var usesSpatialFocus: Bool {
        return arrangement != .dwindle || rootTilingContainer.layout == .dwindle || rootTilingContainer.layout == .master
    }

    @MainActor
    func normalizeMasterLayout() {
        // `default-root-container-layout = 'master'` still creates a master root, as it did
        // before arrangements: turn it into the Master arrangement once.
        if arrangement == .dwindle, rootTilingContainer.layout == .master {
            rootTilingContainer.layout = .tiles
            transitionArrangement(to: .master)
        }
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
           workspace.rootTilingContainer.layout == .tabGroup {
            return workspace.rootTilingContainer
        }
        let groups = nodeWorkspace?.arrangementGroupParent
        var node: TreeNode = self
        while let parent = node.parent as? TilingContainer, parent !== groups, !(parent.parent is Workspace) {
            node = parent
        }
        return node
    }
}

extension Workspace {
    /// The container whose children Master arranges: the root, except that
    /// Master looks inside a root holding a single split (a row or column made in Dwindle),
    /// which would otherwise be one group shown whole. The tree is not changed.
    @MainActor
    var arrangementGroupParent: TilingContainer {
        let root = rootTilingContainer
        guard arrangement == .master, root.layout != .tabGroup,
              let split = root.children.singleOrNil() as? TilingContainer,
              split.layout != .tabGroup, split.children.count > 1 else { return root }
        return split
    }

    @MainActor
    var workspaceLayoutUnits: [TreeNode] {
        let root = arrangementGroupParent
        let units = root.layout == .tabGroup ? [root] : root.children
        return units
    }
}
