import Common

extension Workspace {
    /// Puts a new tiles split of `orientation` at the root, holding the old root as its only child,
    /// so windows can go beside it. Returns the new root.
    @MainActor
    @discardableResult
    func wrapRootTilingContainer(orientation: Orientation) -> TilingContainer {
        let previousRoot = rootTilingContainer
        previousRoot.unbindFromParent()
        let root = TilingContainer(parent: self, adaptiveWeight: WEIGHT_AUTO, orientation, .tiles, index: 0)
        previousRoot.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: 0)
        return root
    }
}

/// A root that is a tab group shows one window at a time, so columns need a split around it.
@MainActor
@discardableResult
func ensureRootSupportsColumns(_ workspace: Workspace) -> TilingContainer {
    let root = workspace.rootTilingContainer
    guard root.layout == .tabGroup else { return root }
    return workspace.wrapRootTilingContainer(orientation: root.orientation)
}
