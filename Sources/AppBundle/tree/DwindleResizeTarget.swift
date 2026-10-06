import AppKit
import Common

/// A split divides its leading child from all children that follow it.
struct DwindleResizeTarget {
    let container: TilingContainer
    let splitIndex: Int
    let orientation: Orientation
    let availableLength: CGFloat
    let leadingLength: CGFloat
    let resizesLeadingChild: Bool
    let resizeEdge: CGFloat
    var resizedChildIndex: Int? = nil

    @MainActor
    func resize(_ units: ResizeCmdArgs.Units) -> Bool {
        if container.isExplicitDwindle, let index = resizedChildIndex,
           let rect = container.lastAppliedLayoutPhysicalRect, let workspace = container.nodeWorkspace {
            let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
            let extent = rect.getDimension(orientation) - CGFloat(gaps.inner.get(orientation).toDouble()) * CGFloat(container.children.count - 1)
            guard extent > 0 else { return false }
            let shares = container.dwindleShares(count: container.children.count)
            let old = shares[index]
            let current = container.children[index].lastAppliedLayoutPhysicalRect?.getDimension(orientation) ?? old * extent
            let delta: CGFloat = switch units {
                case .set(let value): CGFloat(value) - current
                case .add(let value): CGFloat(value)
                case .subtract(let value): -CGFloat(value)
            }
            let smallestOther = shares.enumerated().filter { $0.offset != index }.map(\.element).min() ?? 1
            let minimum = container.children[index].minimumLayoutExtent(along: orientation, gaps: gaps, rect: rect)
            let lower = max(0.1, min(minimum / extent, old))
            let upper = 1 - 0.1 * (1 - old) / smallestOther
            guard upper >= lower else { return false }
            let next = min(max(old + delta / extent, lower), upper)
            guard abs(next - old) > 0.000000001, old < 1 else { return false }
            let before = container.dwindleChildFrames(in: rect, gaps: gaps)
            let previous = container.dwindleChildRatios
            container.dwindleChildRatios = shares.enumerated().map {
                $0.offset == index ? next : $0.element * (1 - next) / (1 - old)
            }
            if before[index] == container.dwindleChildFrames(in: rect, gaps: gaps)[index] {
                container.dwindleChildRatios = previous
                return false
            }
            return true
        }
        guard availableLength > 0 else { return false }
        let currentLength = resizesLeadingChild ? leadingLength : availableLength - leadingLength
        let requestedLength: CGFloat = switch units {
            case .set(let value): CGFloat(value)
            case .add(let value): currentLength + CGFloat(value)
            case .subtract(let value): currentLength - CGFloat(value)
        }
        let ratio = ratio(forLength: requestedLength)
        guard ratio != container.dwindleSplitRatio(at: splitIndex) else { return false }
        if let rect = container.lastAppliedLayoutPhysicalRect, let workspace = container.nodeWorkspace {
            let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
            let before = container.dwindleChildFrames(in: rect, gaps: gaps)
            let after = container.dwindleChildFrames(in: rect, gaps: gaps) {
                $0 == splitIndex ? ratio : container.dwindleSplitRatio(at: $0)
            }
            guard before != after else { return false }
        }
        container.setDwindleSplitRatio(ratio, at: splitIndex)
        return true
    }

    func ratio(forLength length: CGFloat) -> CGFloat {
        guard availableLength > 0 else { return 0.5 }
        let leading = resizesLeadingChild ? length : availableLength - length
        let bounds = container.dwindlePairRatioBounds(at: splitIndex)
        return min(max(leading / availableLength, bounds.lowerBound), bounds.upperBound)
    }
}

extension TreeNode {
    @MainActor
    func dwindleResizeTargets(geometry: [ObjectIdentifier: Rect]? = nil) -> [DwindleResizeTarget] {
        guard let container = parent as? TilingContainer, container.layout == .dwindle,
              let ownIndex, let rect = geometry?[ObjectIdentifier(container)] ?? container.lastAppliedLayoutPhysicalRect,
              let workspace = nodeWorkspace else { return [] }
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
        if container.isExplicitDwindle {
            let axis = container.dwindleAxis(width: rect.width, height: rect.height)
            let gap = CGFloat(gaps.inner.get(axis).toDouble())
            return [ownIndex, ownIndex - 1].compactMap { index in
                guard index >= 0, index + 1 < container.children.count,
                      let a = geometry?[ObjectIdentifier(container.children[index])] ?? container.children[index].lastAppliedLayoutPhysicalRect,
                      let b = geometry?[ObjectIdentifier(container.children[index + 1])] ?? container.children[index + 1].lastAppliedLayoutPhysicalRect else { return nil }
                return DwindleResizeTarget(container: container, splitIndex: index, orientation: axis,
                    availableLength: a.getDimension(axis) + b.getDimension(axis),
                    leadingLength: a.getDimension(axis), resizesLeadingChild: index == ownIndex,
                    resizeEdge: (axis == .h ? a.maxX : a.maxY) + (index == ownIndex ? 0 : gap), resizedChildIndex: ownIndex)
            }
        }
        var width = rect.width
        var height = rect.height
        var targets: [DwindleResizeTarget] = []
        for index in 0..<min(ownIndex + 1, max(container.children.count - 1, 0)) {
            guard let childRect = geometry?[ObjectIdentifier(container.children[index])] ?? container.children[index].lastAppliedLayoutPhysicalRect else { return [] }
            let orientation: Orientation = container.dwindleAxis(width: width, height: height)
            let gap = CGFloat(gaps.inner.get(orientation).toDouble())
            let leadingLength = childRect.getDimension(orientation)
            targets.append(DwindleResizeTarget(
                container: container, splitIndex: index, orientation: orientation,
                availableLength: max((orientation == .h ? width : height) - gap, 0),
                leadingLength: leadingLength, resizesLeadingChild: index == ownIndex,
                resizeEdge: (orientation == .h ? childRect.maxX : childRect.maxY) + (index == ownIndex ? 0 : gap),
            ))
            if orientation == .h { width = max(width - leadingLength - gap, 0) }
            else { height = max(height - leadingLength - gap, 0) }
        }
        return targets.reversed()
    }
}

enum WindowResizeCommandTarget {
    case tiles(TreeNode, TilingContainer)
    case dwindle(DwindleResizeTarget)

    var orientation: Orientation {
        switch self {
            case .tiles(_, let parent): parent.orientation
            case .dwindle(let target): target.orientation
        }
    }
}
