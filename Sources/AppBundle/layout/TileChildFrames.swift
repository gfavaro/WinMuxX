import AppKit
import Common

extension TilingContainer {
    @MainActor
    func tileChildFrames(in rect: Rect, gaps: ResolvedGaps, weightAt: ((TreeNode) -> CGFloat)? = nil) -> [(physical: Rect, virtual: Rect, weight: CGFloat)] {
        guard !children.isEmpty else { return [] }
        let axis = orientation
        let extent = rect.getDimension(axis)
        let gap = CGFloat(gaps.inner.get(axis).toDouble())
        var requested = children.map { weightAt?($0) ?? $0.getWeight(axis) }
        if layout == .master {
            let total = requested.reduce(0, +)
            if total > 0 { requested = requested.map { $0 / total * extent } }
        }
        let edgeGaps = children.indices.map { index in
            gap - (index == 0 ? gap / 2 : 0) - (index == children.count - 1 ? gap / 2 : 0)
        }
        let minimums = children.map { $0.minimumLayoutExtent(along: axis, gaps: gaps, rect: rect) }
        let sizes: [CGFloat]
        if minimums.allSatisfy({ $0 == 0 }) {
            let delta = (extent - requested.reduce(0, +)) / CGFloat(children.count)
            sizes = requested.map { max($0 + delta, 0) }
        } else {
            // Tile weights include their share of the gap; learned minimums describe content.
            sizes = fitLayoutSizes(requested, minimums: zip(minimums, edgeGaps).map(+), total: extent)
        }
        var point = rect.topLeftCorner
        return children.indices.map { index in
            let size = sizes[index]
            let childPoint = index == 0 ? point : point.addingOffset(axis, gap / 2)
            let physical = Rect(topLeftX: childPoint.x, topLeftY: childPoint.y,
                width: axis == .h ? max(size - edgeGaps[index], 0) : rect.width,
                height: axis == .v ? max(size - edgeGaps[index], 0) : rect.height)
            let virtual = Rect(topLeftX: point.x, topLeftY: point.y,
                width: axis == .h ? size : rect.width, height: axis == .v ? size : rect.height)
            point = point.addingOffset(axis, size)
            if layout == .master, config.master.side.isReversed {
                func mirrored(_ frame: Rect) -> Rect {
                    Rect(topLeftX: axis == .h ? rect.minX + rect.maxX - frame.maxX : frame.minX,
                         topLeftY: axis == .v ? rect.minY + rect.maxY - frame.maxY : frame.minY,
                         width: frame.width, height: frame.height)
                }
                return (mirrored(physical), mirrored(virtual), size)
            }
            return (physical, virtual, size)
        }
    }
}
