import AppKit
import Common

final class TilingContainer: TreeNode, NonLeafTreeNodeObject { // todo consider renaming to GenericContainer
    fileprivate var _orientation: Orientation
    var orientation: Orientation { _orientation }
    var layout: Layout
    // Each entry controls a child versus the remaining subtree, not sibling weights.
    var dwindleSplitRatios: [CGFloat] = []
    // nil resolves each split from the available rectangle.
    var dwindleOrientation: Orientation?
    // nil denotes the legacy implicit spine; explicit containers store sibling shares.
    var dwindleChildRatios: [CGFloat]?
    var isExplicitDwindle: Bool { dwindleChildRatios != nil }

    func dwindleAxis(width: CGFloat, height: CGFloat) -> Orientation {
        dwindleOrientation ?? (width >= height ? .h : .v)
    }

    @MainActor
    var navigationOrientation: Orientation {
        guard layout == .dwindle else { return orientation }
        let rect = lastAppliedLayoutPhysicalRect ?? nodeMonitor?.visibleRectPaddedByOuterGaps
        return rect.map { dwindleAxis(width: $0.width, height: $0.height) } ?? dwindleOrientation ?? orientation
    }

    func dwindleShares(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        if let ratios = dwindleChildRatios {
            let valid = ratios.count == count && ratios.allSatisfy { $0.isFinite && $0 > 0 }
            let values = valid ? ratios : Array(repeating: CGFloat(1), count: count)
            let total = values.reduce(0, +)
            return values.map { $0 / total }
        }
        var remaining: CGFloat = 1
        return (0..<count).map { index in
            let share = index == count - 1 ? remaining : remaining * dwindleSplitRatio(at: index)
            remaining -= share
            return share
        }
    }

    func setDwindleShares(_ shares: [CGFloat]) {
        if isExplicitDwindle { dwindleChildRatios = shares; return }
        var remaining = shares.reduce(0, +)
        dwindleSplitRatios = shares.dropLast().map { share in
            let ratio = remaining > 0 ? share / remaining : 0.5
            remaining -= share
            return min(max(ratio, 0.1), 0.9)
        }
    }

    func dwindleChildWillInsert(at index: Int) {
        if layout == .dwindle, isExplicitDwindle {
            let count = children.count
            var shares = dwindleShares(count: count).map { $0 * CGFloat(count) / CGFloat(count + 1) }
            shares.insert(1 / CGFloat(count + 1), at: index)
            dwindleChildRatios = shares
            return
        }
        guard layout == .dwindle, !dwindleSplitRatios.isEmpty else { return }
        var shares = dwindleShares(count: children.count)
        guard !shares.isEmpty else { return }
        let donor = min(max(index - 1, 0), shares.count - 1)
        let share = shares[donor] / 2
        shares[donor] = share
        shares.insert(share, at: index)
        setDwindleShares(shares)
    }

    func dwindleChildWillRemove(at index: Int) {
        guard layout == .dwindle else { return }
        if isExplicitDwindle {
            var shares = dwindleShares(count: children.count)
            shares.remove(at: index)
            let total = shares.reduce(0, +)
            dwindleChildRatios = total > 0 ? shares.map { $0 / total } : []
            return
        }
        // The flat list represents a binary spine, not a row of weighted siblings.
        // Removing a leaf collapses its split: the sibling inherits that entire
        // rectangle, while ancestors and surviving tail splits keep their ratios.
        let count = children.count
        guard count > 1 else { dwindleSplitRatios = []; return }
        var ratios = (0..<(count - 1)).map { dwindleSplitRatio(at: $0) }
        ratios.remove(at: min(index, count - 2))
        dwindleSplitRatios = ratios
    }

    func dwindleSplitRatio(at index: Int) -> CGFloat {
        if isExplicitDwindle {
            let shares = dwindleShares(count: children.count)
            guard index >= 0, index + 1 < shares.count else { return 0.5 }
            return shares[index] / (shares[index] + shares[index + 1])
        }
        guard dwindleSplitRatios.indices.contains(index), dwindleSplitRatios[index].isFinite else { return 0.5 }
        return min(max(dwindleSplitRatios[index], 0.1), 0.9)
    }

    func setDwindleSplitRatio(_ ratio: CGFloat, at index: Int) {
        guard index >= 0, index < children.count - 1, ratio.isFinite else { return }
        if isExplicitDwindle {
            var shares = dwindleShares(count: children.count)
            let total = shares[index] + shares[index + 1]
            let bounds = dwindlePairRatioBounds(at: index)
            shares[index] = total * min(max(ratio, bounds.lowerBound), bounds.upperBound)
            shares[index + 1] = total - shares[index]
            dwindleChildRatios = shares
            return
        }
        if dwindleSplitRatios.count <= index {
            dwindleSplitRatios.append(contentsOf: repeatElement(0.5, count: index + 1 - dwindleSplitRatios.count))
        }
        dwindleSplitRatios[index] = min(max(ratio, 0.1), 0.9)
    }

    func dwindlePairRatioBounds(at index: Int) -> ClosedRange<CGFloat> {
        guard isExplicitDwindle else { return 0.1...0.9 }
        let shares = dwindleShares(count: children.count)
        guard index >= 0, index + 1 < shares.count else { return 0.1...0.9 }
        let total = shares[index] + shares[index + 1]
        return (min(shares[index], 0.1) / total)...(1 - min(shares[index + 1], 0.1) / total)
    }

    @MainActor
    init(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, _ orientation: Orientation, _ layout: Layout, index: Int) {
        self._orientation = orientation
        self.layout = layout
        if parent is Workspace, layout == .dwindle {
            dwindleOrientation = switch config.defaultRootContainerOrientation {
                case .auto: nil
                case .horizontal: .h
                case .vertical: .v
            }
        }
        super.init(parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor
    static func newHTiles(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) -> TilingContainer {
        TilingContainer(parent: parent, adaptiveWeight: adaptiveWeight, .h, .tiles, index: index)
    }

    @MainActor
    static func newVTiles(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) -> TilingContainer {
        TilingContainer(parent: parent, adaptiveWeight: adaptiveWeight, .v, .tiles, index: index)
    }
}

extension TilingContainer {
    var isRootContainer: Bool { parent is Workspace }

    @MainActor
    func changeOrientation(_ targetOrientation: Orientation) {
        if orientation == targetOrientation {
            return
        }
        if config.enableNormalizationOppositeOrientationForNestedContainers {
            var orientation = targetOrientation
            parentsWithSelf
                .filterIsInstance(of: TilingContainer.self)
                .forEach {
                    $0._orientation = orientation
                    orientation = orientation.opposite
                }
        } else {
            _orientation = targetOrientation
        }
    }

    func normalizeOppositeOrientationForNestedContainers() {
        if orientation == (parent as? TilingContainer)?.orientation {
            _orientation = orientation.opposite
        }
        for child in children {
            (child as? TilingContainer)?.normalizeOppositeOrientationForNestedContainers()
        }
    }
}

enum Layout: String, Codable {
    case tiles
    case tabGroup = "tab-group"
    case dwindle
}

extension String {
    func parseLayout() -> Layout? {
        Layout(rawValue: self)
    }
}
