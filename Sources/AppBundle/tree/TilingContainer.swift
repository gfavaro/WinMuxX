import AppKit
import Common

final class TilingContainer: TreeNode, NonLeafTreeNodeObject { // todo consider renaming to GenericContainer
    fileprivate var _orientation: Orientation
    var orientation: Orientation { _orientation }
    var isMasterStack = false
    var appliedMasterConfig: MasterConfig?
    var masterRatio: CGFloat?
    var layout: Layout {
        didSet {
            if oldValue != layout, oldValue == .master || layout == .master {
                masterRatio = nil
                appliedMasterConfig = nil
            }
        }
    }
    /// Each child's share of a Dwindle split along `dwindleOrientation`; a count that does not
    /// match the children gives them equal shares.
    var dwindleChildRatios: [CGFloat] = []
    // nil resolves the split's axis from the available rectangle.
    var dwindleOrientation: Orientation?

    func dwindleAxis(width: CGFloat, height: CGFloat) -> Orientation {
        dwindleOrientation ?? (width >= height ? .h : .v)
    }

    /// The direction this split was made in. Dwindle navigates by the shape it last had on screen
    /// (`navigationOrientation`); other layouts read the tree by this, which a resize cannot change.
    var declaredOrientation: Orientation {
        layout == .dwindle ? dwindleOrientation ?? orientation : orientation
    }

    @MainActor
    var navigationOrientation: Orientation {
        guard layout == .dwindle else { return orientation }
        let rect = lastAppliedLayoutPhysicalRect ?? nodeMonitor?.visibleRectPaddedByOuterGaps
        return rect.map { dwindleAxis(width: $0.width, height: $0.height) } ?? dwindleOrientation ?? orientation
    }

    func dwindleShares(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let valid = dwindleChildRatios.count == count && dwindleChildRatios.allSatisfy { $0.isFinite && $0 > 0 }
        let values = valid ? dwindleChildRatios : Array(repeating: CGFloat(1), count: count)
        let total = values.reduce(0, +)
        return values.map { $0 / total }
    }

    func dwindleChildWillInsert(at index: Int) {
        guard layout == .dwindle else { return }
        let count = children.count
        var shares = dwindleShares(count: count).map { $0 * CGFloat(count) / CGFloat(count + 1) }
        shares.insert(1 / CGFloat(count + 1), at: index)
        dwindleChildRatios = shares
    }

    func dwindleChildWillRemove(at index: Int) {
        guard layout == .dwindle else { return }
        var shares = dwindleShares(count: children.count)
        shares.remove(at: index)
        let total = shares.reduce(0, +)
        dwindleChildRatios = total > 0 ? shares.map { $0 / total } : []
    }

    /// How a pair of neighbours splits what the two share: the leading one's part of it.
    func dwindleSplitRatio(at index: Int) -> CGFloat {
        let shares = dwindleShares(count: children.count)
        guard index >= 0, index + 1 < shares.count else { return 0.5 }
        return shares[index] / (shares[index] + shares[index + 1])
    }

    func setDwindleSplitRatio(_ ratio: CGFloat, at index: Int) {
        guard index >= 0, index < children.count - 1, ratio.isFinite else { return }
        var shares = dwindleShares(count: children.count)
        let total = shares[index] + shares[index + 1]
        let bounds = dwindlePairRatioBounds(at: index)
        shares[index] = total * min(max(ratio, bounds.lowerBound), bounds.upperBound)
        shares[index + 1] = total - shares[index]
        dwindleChildRatios = shares
    }

    func dwindlePairRatioBounds(at index: Int) -> ClosedRange<CGFloat> {
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

enum Layout: String {
    case tiles
    case tabGroup = "tab-group"
    case dwindle
    case master
}

/// Saved state from before accordion was removed still says "accordion"; it loads as a tab group.
extension Layout: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let layout = raw.parseLayout() else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown layout \(raw)"))
        }
        self = layout
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension String {
    func parseLayout() -> Layout? {
        // Accordion was removed; configs and commands naming it get a tab group, as AeroSpace import does.
        Layout(rawValue: ["tabbed", "accordion", "stacked"].contains(self) ? "tab-group" : self)
    }
}
