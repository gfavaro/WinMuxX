extension Workspace {
    @MainActor func normalizeContainers() {
        if preservesTopLevelGroups {
            rootTilingContainer.removeEmptyArrangementContainers()
            // Group boundaries stay as they are, but a split left holding a single child marks
            // none: without this, the one-child wrappers Dwindle leaves behind would pile up.
            rootTilingContainer.flattenSingleChildWrappers()
            normalizeMasterLayout()
            return
        }
        normalizeMasterLayout()
        materializeDwindleTree()
        rootTilingContainer.unbindEmptyAndAutoFlatten() // Beware! rootTilingContainer may change after this line of code
        // Dwindle splits choose their axis from the available rectangle, not their parent's axis.
        if config.enableNormalizationOppositeOrientationForNestedContainers && rootTilingContainer.layout != .dwindle && rootTilingContainer.layout != .master {
            rootTilingContainer.normalizeOppositeOrientationForNestedContainers()
        }
    }
}

extension TilingContainer {
    @MainActor fileprivate func removeEmptyArrangementContainers() {
        for child in children {
            (child as? TilingContainer)?.removeEmptyArrangementContainers()
        }
        if children.isEmpty && !isRootContainer { unbindFromParent() }
    }

    /// Replaces every split below the root that holds a single child with that child, which takes
    /// the split's place, share and saved column widths; tab groups stay, being one column of tabs.
    @MainActor fileprivate func flattenSingleChildWrappers() {
        for child in children {
            (child as? TilingContainer)?.flattenSingleChildWrappers()
        }
        guard !isRootContainer, layout != .tabGroup, let only = children.singleOrNil(),
              let parent = parent as? TilingContainer else { return }
        let siblingRatios = parent.dwindleChildRatios
        let wasMostRecent = parent.mostRecentChild === self
        let columnWidth = scrollingColumnWidth
        only.unbindFromParent()
        let binding = unbindFromParent()
        only.bind(to: parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
        if only.scrollingColumnWidth == nil { only.scrollingColumnWidth = columnWidth }
        parent.dwindleChildRatios = siblingRatios
        if wasMostRecent { only.markAsMostRecentChild() }
    }

    @MainActor fileprivate func unbindEmptyAndAutoFlatten() {
        // Keep the dwindle root: it carries the insertion policy even when its only child is a tiles split.
        let preservesDwindleRoot = (isRootContainer && (layout == .dwindle || layout == .master)) || (parent as? TilingContainer)?.layout == .master
        if let child = children.singleOrNil(), config.enableNormalizationFlattenContainers && !preservesDwindleRoot && (child is TilingContainer || !isRootContainer) {
            let dwindleParent = parent as? TilingContainer
            let siblingRatios = dwindleParent?.dwindleChildRatios
            child.unbindFromParent()
            let mru = parent?.mostRecentChild
            let previousBinding = unbindFromParent()
            child.bind(to: previousBinding.parent, adaptiveWeight: previousBinding.adaptiveWeight, index: previousBinding.index)
            if let siblingRatios { dwindleParent?.dwindleChildRatios = siblingRatios }
            (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            if mru != self {
                mru?.markAsMostRecentChild()
            } else {
                child.markAsMostRecentChild()
            }
        } else {
            for child in children {
                (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            }
            if children.isEmpty && !isRootContainer {
                unbindFromParent()
            }
            normalizeExplicitDwindle()
        }
    }
}
