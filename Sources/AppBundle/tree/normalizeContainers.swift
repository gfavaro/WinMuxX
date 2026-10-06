extension Workspace {
    @MainActor func normalizeContainers() {
        materializeDwindleTree()
        rootTilingContainer.unbindEmptyAndAutoFlatten() // Beware! rootTilingContainer may change after this line of code
        // Dwindle splits choose their axis from the available rectangle, not their parent's axis.
        if config.enableNormalizationOppositeOrientationForNestedContainers && rootTilingContainer.layout != .dwindle {
            rootTilingContainer.normalizeOppositeOrientationForNestedContainers()
        }
    }
}

extension TilingContainer {
    @MainActor fileprivate func unbindEmptyAndAutoFlatten() {
        // Keep the dwindle root: it carries the insertion policy even when its only child is a tiles split.
        let preservesDwindleRoot = isRootContainer && layout == .dwindle
        if let child = children.singleOrNil(), config.enableNormalizationFlattenContainers && !preservesDwindleRoot && (child is TilingContainer || !isRootContainer) {
            let dwindleParent = parent as? TilingContainer
            let ratios = dwindleParent?.dwindleSplitRatios
            let siblingRatios = dwindleParent?.dwindleChildRatios
            child.unbindFromParent()
            let mru = parent?.mostRecentChild
            let previousBinding = unbindFromParent()
            child.bind(to: previousBinding.parent, adaptiveWeight: previousBinding.adaptiveWeight, index: previousBinding.index)
            if let ratios { dwindleParent?.dwindleSplitRatios = ratios }
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
