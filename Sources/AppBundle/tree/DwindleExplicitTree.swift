import AppKit
import Common

extension Workspace {
    /// Tiles splits inside a Dwindle root become Dwindle splits with the shares they had on screen.
    @MainActor
    func materializeDwindleTree() {
        guard rootTilingContainer.layout == .dwindle else { return }
        let recent = rootTilingContainer.mostRecentWindowRecursive
        rootTilingContainer.materializeDwindle(in: dwindleConversionRect, gaps: dwindleConversionGaps)
        recent?.markAsMostRecentChild()
    }

    /// Lays the root's children out as a Dwindle spiral; see `adoptDwindleSpiral`.
    @MainActor
    func adoptDwindleSpiral(ratios: [CGFloat] = []) {
        let recent = rootTilingContainer.mostRecentWindowRecursive
        rootTilingContainer.adoptDwindleSpiral(ratios: ratios, in: dwindleConversionRect, gaps: dwindleConversionGaps)
        recent?.markAsMostRecentChild()
    }

    /// Rebuilds the splits a restore found saved as spirals (by `ObjectIdentifier`, with their
    /// ratios), from the top, so each gets the area its parent gives it.
    @MainActor
    func adoptRestoredDwindleSpirals(_ spirals: [ObjectIdentifier: [CGFloat]]) {
        guard !spirals.isEmpty else { return }
        let recent = rootTilingContainer.mostRecentWindowRecursive
        rootTilingContainer.adoptDwindleSpirals(spirals, in: dwindleConversionRect, gaps: dwindleConversionGaps)
        recent?.markAsMostRecentChild()
    }

    @MainActor private var dwindleConversionRect: Rect {
        rootTilingContainer.lastAppliedLayoutPhysicalRect ?? workspaceMonitor.visibleRectPaddedByOuterGaps
    }

    @MainActor private var dwindleConversionGaps: ResolvedGaps { ResolvedGaps(gaps: config.gaps, monitor: workspaceMonitor) }
}

extension TilingContainer {
    @MainActor
    fileprivate func materializeDwindle(in rect: Rect, gaps: ResolvedGaps) {
        if layout == .tiles {
            let frames = tileChildFrames(in: rect, gaps: gaps)
            layout = .dwindle
            dwindleOrientation = orientation
            dwindleChildRatios = frames.map { $0.physical.getDimension(orientation) }
        }
        if layout == .tabGroup { return }
        let frames = dwindleChildFrames(in: rect, gaps: gaps)
        for (node, frame) in zip(children, frames) {
            (node as? TilingContainer)?.materializeDwindle(in: frame, gaps: gaps)
        }
    }

    /// Becomes a Dwindle spiral of its children, as older WinMuxX kept them in one list: the first
    /// takes `ratios[0]` of the area, the rest share what is left, split again the same way.
    /// Builds it as nested splits of two. Old saved state, a Tiles root switched to Dwindle and the
    /// old Master tree come in this way.
    @MainActor
    func adoptDwindleSpiral(ratios: [CGFloat], in rect: Rect, gaps: ResolvedGaps) {
        let nodes = children
        let fixedAxis = dwindleOrientation
        for node in nodes { node.unbindFromParent() }
        layout = .dwindle
        dwindleChildRatios = []
        populateDwindleSpiral(nodes: nodes[...], ratios: ratios[...], rect: rect, gaps: gaps, fixedAxis: fixedAxis)
    }

    /// Becomes a Dwindle spiral in the area it was last laid out in, as a configured Dwindle
    /// root layout does.
    @MainActor
    func adoptDwindleSpiral() {
        guard let workspace = nodeWorkspace else { layout = .dwindle; return }
        let monitor = workspace.workspaceMonitor
        adoptDwindleSpiral(ratios: [], in: lastAppliedLayoutPhysicalRect ?? monitor.visibleRectPaddedByOuterGaps,
                           gaps: ResolvedGaps(gaps: config.gaps, monitor: monitor))
    }

    @MainActor
    fileprivate func adoptDwindleSpirals(_ spirals: [ObjectIdentifier: [CGFloat]], in rect: Rect, gaps: ResolvedGaps) {
        if let ratios = spirals[ObjectIdentifier(self)] { adoptDwindleSpiral(ratios: ratios, in: rect, gaps: gaps) }
        let frames: [Rect] = switch layout {
            case .dwindle: dwindleChildFrames(in: rect, gaps: gaps)
            case .tiles: tileChildFrames(in: rect, gaps: gaps).map(\.physical)
            case .tabGroup, .master: children.map { _ in rect }
        }
        for (node, frame) in zip(children, frames) {
            (node as? TilingContainer)?.adoptDwindleSpirals(spirals, in: frame, gaps: gaps)
        }
    }

    @MainActor
    private func populateDwindleSpiral(nodes: ArraySlice<TreeNode>, ratios: ArraySlice<CGFloat>, rect: Rect,
                                       gaps: ResolvedGaps, fixedAxis: Orientation?) {
        guard let first = nodes.first else { return }
        first.bind(to: self, adaptiveWeight: 1, index: 0)
        guard nodes.count > 1 else { dwindleChildRatios = [1]; return }
        let axis = fixedAxis ?? (rect.width >= rect.height ? .h : .v)
        dwindleOrientation = axis
        let ratio = ratios.first.flatMap { $0.isFinite ? min(max($0, 0.1), 0.9) : nil } ?? 0.5
        if nodes.count == 2 {
            nodes.last!.bind(to: self, adaptiveWeight: 1, index: 1)
        } else {
            let gap = CGFloat(gaps.inner.get(axis).toDouble())
            let length = rect.getDimension(axis)
            let consumed = max(length - gap, 0) * ratio + gap
            let tail = axis == .h
                ? Rect(topLeftX: rect.topLeftX + consumed, topLeftY: rect.topLeftY, width: max(length - consumed, 0), height: rect.height)
                : Rect(topLeftX: rect.topLeftX, topLeftY: rect.topLeftY + consumed, width: rect.width, height: max(length - consumed, 0))
            let tailAxis = fixedAxis ?? (tail.width >= tail.height ? Orientation.h : .v)
            let branch = TilingContainer(parent: self, adaptiveWeight: 1, tailAxis, .dwindle, index: 1)
            branch.populateDwindleSpiral(nodes: nodes.dropFirst(), ratios: ratios.dropFirst(), rect: tail, gaps: gaps,
                                         fixedAxis: fixedAxis)
        }
        dwindleChildRatios = [ratio, 1 - ratio]
    }

    /// Dinky keeps a promoted child's axis and proportionally splices matching axes.
    @MainActor
    func normalizeExplicitDwindle() {
        guard layout == .dwindle else { return }
        let recent = mostRecentWindowRecursive
        while let only = children.singleOrNil() as? TilingContainer,
              only.layout == .dwindle {
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
               branch.dwindleOrientation == axis {
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
