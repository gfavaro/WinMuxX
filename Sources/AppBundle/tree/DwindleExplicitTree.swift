import AppKit
import Common

extension Workspace {
    /// Upgrade the old implicit spine without flattening it or resetting resized slots.
    @MainActor
    func materializeDwindleTree() {
        guard rootTilingContainer.layout == .dwindle else { return }
        let recent = rootTilingContainer.mostRecentWindowRecursive
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspaceMonitor)
        let rect = rootTilingContainer.lastAppliedLayoutPhysicalRect ?? workspaceMonitor.visibleRectPaddedByOuterGaps
        rootTilingContainer.materializeDwindle(in: rect, gaps: gaps)
        recent?.markAsMostRecentChild()
    }
}

extension TilingContainer {
    @MainActor
    fileprivate func materializeDwindle(in rect: Rect, gaps: ResolvedGaps) {
        if layout == .tiles {
            let frames = tileChildFrames(in: rect, gaps: gaps)
            layout = .dwindle
            dwindleOrientation = orientation
            dwindleChildRatios = frames.map { $0.physical.getDimension(orientation) }
        } else if layout == .dwindle, !isExplicitDwindle {
            let nodes = children
            let ratios = (0..<max(nodes.count - 1, 0)).map { dwindleSplitRatio(at: $0) }
            let legacyAxis = dwindleOrientation
            let frames = dwindleChildFrames(in: rect, gaps: gaps)
            for node in nodes { node.unbindFromParent() }
            dwindleSplitRatios = []
            dwindleChildRatios = []
            if nodes.count > 1 { dwindleOrientation = legacyAxis ?? (rect.width >= rect.height ? .h : .v) }
            populateDwindleSpine(nodes: nodes[...], ratios: ratios[...], frames: frames[...], legacyAxis: legacyAxis)
        }
        if layout == .tabGroup { return }
        let frames = dwindleChildFrames(in: rect, gaps: gaps)
        for (node, frame) in zip(children, frames) {
            (node as? TilingContainer)?.materializeDwindle(in: frame, gaps: gaps)
        }
    }

    @MainActor
    private func populateDwindleSpine(nodes: ArraySlice<TreeNode>, ratios: ArraySlice<CGFloat>, frames: ArraySlice<Rect>, legacyAxis: Orientation?) {
        guard let first = nodes.first else { return }
        first.bind(to: self, adaptiveWeight: 1, index: 0)
        guard nodes.count > 1 else { dwindleChildRatios = [1]; return }
        let ratio = ratios.first ?? 0.5
        if nodes.count == 2 {
            nodes.last!.bind(to: self, adaptiveWeight: 1, index: 1)
        } else {
            let tailFrames = frames.dropFirst()
            let x = tailFrames.map(\.minX).min()!
            let y = tailFrames.map(\.minY).min()!
            let tail = Rect(topLeftX: x, topLeftY: y,
                width: tailFrames.map(\.maxX).max()! - x, height: tailFrames.map(\.maxY).max()! - y)
            let axis = legacyAxis ?? (tail.width >= tail.height ? Orientation.h : .v)
            let branch = TilingContainer(parent: self, adaptiveWeight: 1, axis, .dwindle, index: 1)
            branch.dwindleOrientation = axis
            branch.dwindleChildRatios = []
            branch.populateDwindleSpine(nodes: nodes.dropFirst(), ratios: ratios.dropFirst(), frames: tailFrames, legacyAxis: legacyAxis)
        }
        dwindleChildRatios = [ratio, 1 - ratio]
    }

    /// Dinky keeps a promoted child's axis and proportionally splices matching axes.
    @MainActor
    func normalizeExplicitDwindle() {
        guard layout == .dwindle, isExplicitDwindle else { return }
        let recent = mostRecentWindowRecursive
        while let only = children.singleOrNil() as? TilingContainer,
              only.layout == .dwindle, only.isExplicitDwindle {
            let nodes = only.children
            let shares = only.dwindleShares(count: nodes.count)
            let axis = only.dwindleOrientation
            for node in nodes { node.unbindFromParent() }
            only.unbindFromParent()
            for node in nodes { node.bind(to: self, adaptiveWeight: 1, index: INDEX_BIND_LAST) }
            dwindleOrientation = axis
            dwindleChildRatios = shares
        }
        guard let axis = dwindleOrientation else { recent?.markAsMostRecentChild(); return }
        let nodes = children
        let shares = dwindleShares(count: nodes.count)
        var flattened: [TreeNode] = []
        var weights: [CGFloat] = []
        for (node, share) in zip(nodes, shares) {
            if let branch = node as? TilingContainer, branch.layout == .dwindle,
               branch.isExplicitDwindle, branch.dwindleOrientation == axis {
                flattened += branch.children
                weights += branch.dwindleShares(count: branch.children.count).map { $0 * share }
            } else {
                flattened.append(node)
                weights.append(share)
            }
        }
        if flattened != nodes {
            for node in nodes { node.unbindFromParent() }
            for node in flattened { node.bind(to: self, adaptiveWeight: 1, index: INDEX_BIND_LAST) }
            dwindleChildRatios = weights
        }
        recent?.markAsMostRecentChild()
    }
}
