import AppKit
import Common

extension TilingContainer {
    @MainActor
    func tileChildFrames(in rect: Rect, gaps: ResolvedGaps, weightAt: ((TreeNode) -> CGFloat)? = nil) -> [(physical: Rect, virtual: Rect, weight: CGFloat)] {
        guard !children.isEmpty else { return [] }
        let axis = orientation
        let horizontal = axis == .h
        let weights = children.map { weightAt?($0) ?? $0.getWeight(axis) }
        let minimums = children.map { $0.minimumLayoutExtent(along: axis, gaps: gaps, rect: rect) }
        let calculated = TileLayoutGeometry.calculate(TileLayoutInput(
            origin: rect.topLeftCorner, size: rect.size, horizontal: horizontal,
            innerGap: CGFloat(gaps.inner.get(axis).toDouble()), weights: weights,
            minimumExtents: minimums, master: layout == .master,
            reversed: layout == .master && config.master.side.isReversed))
        return calculated.map { frame in
            (Rect(topLeftX: frame.physical.minX, topLeftY: frame.physical.minY,
                  width: frame.physical.width, height: frame.physical.height),
             Rect(topLeftX: frame.virtual.minX, topLeftY: frame.virtual.minY,
                  width: frame.virtual.width, height: frame.virtual.height), frame.weight)
        }
    }
}
