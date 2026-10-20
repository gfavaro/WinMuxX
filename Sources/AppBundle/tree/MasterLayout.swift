import AppKit
import Common

/// A master workspace has two logical children: the primary pane and a stack.
/// The stack and tab groups remain ordinary tree nodes; no separate window model.
extension Workspace {
    @MainActor
    func configureMasterLayout(focused window: Window?) {
        let previousRoot = rootTilingContainer
        if previousRoot.layout == .master, previousRoot.masterRatio != nil {
            normalizeMasterLayout()
            if let window { _ = promoteToMaster(window) }
            return
        }
        var seen = Set<ObjectIdentifier>()
        let units = previousRoot.allLeafWindowsRecursive.map(\.moveNode).filter { seen.insert(ObjectIdentifier($0)).inserted }
        let primary = window?.moveNode
        let ordered = units.filter { $0 === primary } + units.filter { $0 !== primary }
        // A root tab group is itself an atomic pane.
        let root: TilingContainer
        if units.contains(where: { $0 === previousRoot }) {
            previousRoot.unbindFromParent()
            root = TilingContainer(parent: self, adaptiveWeight: 1, config.master.side.orientation, .master, index: 0)
        } else {
            for node in units { node.unbindFromParent() }
            for child in previousRoot.children { child.unbindFromParent() }
            root = previousRoot
            root.layout = .master
        }
        for node in ordered { (node as? TilingContainer)?.isMasterStack = false }
        root.masterStackLayout = config.master.stackLayout
        root.masterRatio = CGFloat(config.master.size)
        root.appliedMasterConfig = config.master
        root.changeOrientation(config.master.side.orientation)
        if let first = ordered.first { first.bind(to: root, adaptiveWeight: CGFloat(config.master.size), index: 0) }
        if ordered.count > 1 {
            let stack = masterStackForInsertion()
            for node in ordered.dropFirst() { node.bind(to: stack, adaptiveWeight: 1, index: INDEX_BIND_LAST) }
        }
    }

    @MainActor
    func masterStackForInsertion() -> TilingContainer {
        let root = rootTilingContainer
        if let stack = root.children.compactMap({ $0 as? TilingContainer }).first(where: \.isMasterStack) { return stack }
        let ratio = root.masterRatio ?? CGFloat(config.master.size)
        let stack = TilingContainer(parent: root, adaptiveWeight: 1 - ratio,
            config.master.side.orientation.opposite, root.masterStackLayout ?? config.master.stackLayout, index: INDEX_BIND_LAST)
        stack.isMasterStack = true
        root.children.first?.setWeight(root.orientation, ratio)
        return stack
    }

    @MainActor
    func normalizeMasterLayout() {
        let root = rootTilingContainer
        guard root.layout == .master else { return }
        if root.masterRatio == nil {
            configureMasterLayout(focused: mostRecentWindowRecursive)
            return
        }
        var ratio = root.masterRatio ?? CGFloat(config.master.size)
        if let previous = root.appliedMasterConfig, previous.size != config.master.size {
            ratio = CGFloat(config.master.size)
        } else if root.children.count == 2,
                  (root.children[1] as? TilingContainer)?.isMasterStack == true {
            // Only an established master/stack pair carries split weights.
            // A pane moved directly into a solo master root inherits its full
            // weight; those temporary siblings must not replace the saved ratio.
            let weights = root.children.map { $0.getWeight(root.orientation) }
            let total = weights.reduce(0, +)
            if total > 0 { ratio = weights[0] / total }
        }
        ratio = ratio.isFinite ? min(max(ratio, 0.1), 0.9) : CGFloat(config.master.size)
        let changedAxis = root.orientation != config.master.side.orientation
        root.changeOrientation(config.master.side.orientation)
        let stackLayout = root.children.compactMap { $0 as? TilingContainer }.first(where: \.isMasterStack)?.layout
        if let previous = root.appliedMasterConfig, previous.stackLayout != config.master.stackLayout {
            root.masterStackLayout = config.master.stackLayout
        } else if root.masterStackLayout == nil {
            root.masterStackLayout = stackLayout ?? config.master.stackLayout
        }
        for child in root.children where child.anyLeafWindowRecursive == nil { child.unbindFromParent() }
        let existingStack = root.children.compactMap { $0 as? TilingContainer }.first(where: \.isMasterStack)
        if let stack = existingStack, !root.children.contains(where: { $0 !== stack }), let next = stack.children.first {
            next.bind(to: root, adaptiveWeight: ratio, index: 0)
        }
        let extras = root.children.filter { $0 !== root.children.first && $0 !== existingStack }
        if !extras.isEmpty {
            let stack = masterStackForInsertion()
            for child in extras { child.bind(to: stack, adaptiveWeight: 1, index: INDEX_BIND_LAST) }
        }
        if let stack = root.children.compactMap({ $0 as? TilingContainer }).first(where: \.isMasterStack) {
            stack.changeOrientation(root.orientation.opposite)
            stack.layout = root.masterStackLayout ?? config.master.stackLayout
            if stack.children.isEmpty { stack.unbindFromParent() }
        }
        if root.children.count == 2 {
            // Keep a dimensionless policy for close/promotion and display changes.
            // Tile geometry scales these weights proportionally before fitting minimums.
            let extent = max(root.lastAppliedLayoutPhysicalRect?.getDimension(root.orientation) ?? 1, 1)
            root.children[0].setWeight(root.orientation, ratio * extent)
            root.children[1].setWeight(root.orientation, (1 - ratio) * extent)
        } else if changedAxis, let first = root.children.first {
            first.setWeight(root.orientation, ratio)
        }
        root.masterRatio = ratio
        root.appliedMasterConfig = config.master
    }

    /// Change only the stack policy, even when its last pane has closed. Avoid
    /// creating an empty container just to remember the next insertion's layout.
    @MainActor
    func changeMasterStackLayout(between layouts: [Layout]) -> Bool {
        normalizeMasterLayout()
        let root = rootTilingContainer
        guard root.layout == .master, !layouts.isEmpty,
              layouts.allSatisfy({ $0 == .tiles || $0 == .stacked }) else { return false }
        let current = root.masterStackLayout ?? config.master.stackLayout
        let target = nextLayout(in: layouts, matching: { $0 == current })
        guard target != current else { return false }
        root.masterStackLayout = target
        if let stack = root.children.compactMap({ $0 as? TilingContainer }).first(where: \.isMasterStack) {
            stack.layout = target
        }
        return true
    }

    @MainActor
    @discardableResult
    func promoteToMaster(_ window: Window) -> Bool {
        let root = rootTilingContainer
        guard root.layout == .master, let master = root.children.first,
              let stack = root.children.compactMap({ $0 as? TilingContainer }).first(where: \.isMasterStack),
              let pane = window.directChild(in: stack) else { return false }
        swapNodes(master, pane)
        return true
    }
}
