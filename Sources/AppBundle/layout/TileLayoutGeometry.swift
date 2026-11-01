import CoreGraphics

/// Immutable input to tile/master allocation. This geometry layer has no access
/// to windows, configuration, monitors, or Accessibility.
struct TileLayoutInput: Equatable {
    let origin: CGPoint
    let size: CGSize
    let horizontal: Bool
    let innerGap: CGFloat
    let weights: [CGFloat]
    let minimumExtents: [CGFloat]
    let master: Bool
    let reversed: Bool
}

struct TileLayoutFrame: Equatable {
    let physical: CGRect
    let virtual: CGRect
    let weight: CGFloat
}

enum TileLayoutGeometry {
    static func calculate(_ input: TileLayoutInput) -> [TileLayoutFrame] {
        guard !input.weights.isEmpty, input.weights.count == input.minimumExtents.count else { return [] }
        let horizontal = input.horizontal
        let extent = horizontal ? input.size.width : input.size.height
        let gap = input.innerGap
        // Weights are scaled to the space, never shifted by equal amounts: a window that comes
        // and goes, or a display that shrinks and grows back, leaves the proportions as they were
        // and cannot squeeze a narrow tile to nothing.
        var requested = input.weights.map { max($0, 0) }
        let total = requested.reduce(0, +)
        requested = total > 0 ? requested.map { $0 / total * extent } : requested.map { _ in extent / CGFloat(requested.count) }
        let edgeGaps = requested.indices.map { index in
            gap - (index == 0 ? gap / 2 : 0) - (index == requested.count - 1 ? gap / 2 : 0)
        }
        let minimums = zip(input.minimumExtents, edgeGaps).map(+)
        let sizes = input.minimumExtents.allSatisfy({ $0 == 0 }) ? requested : fit(requested, minimums: minimums, total: extent)
        var point = input.origin
        return sizes.indices.map { index in
            let size = sizes[index]
            let childPoint = index == 0 ? point : (horizontal ? CGPoint(x: point.x + gap / 2, y: point.y) : CGPoint(x: point.x, y: point.y + gap / 2))
            let physical = CGRect(x: childPoint.x, y: childPoint.y,
                width: horizontal ? max(size - edgeGaps[index], 0) : input.size.width,
                height: horizontal ? input.size.height : max(size - edgeGaps[index], 0))
            let virtual = CGRect(x: point.x, y: point.y,
                width: horizontal ? size : input.size.width,
                height: horizontal ? input.size.height : size)
            point.x += horizontal ? size : 0
            point.y += horizontal ? 0 : size
            func mirror(_ frame: CGRect) -> CGRect {
                CGRect(x: horizontal ? input.origin.x + input.size.width - (frame.maxX - input.origin.x) : frame.minX,
                       y: horizontal ? frame.minY : input.origin.y + input.size.height - (frame.maxY - input.origin.y),
                       width: frame.width, height: frame.height)
            }
            return TileLayoutFrame(physical: input.master && input.reversed ? mirror(physical) : physical,
                                   virtual: input.master && input.reversed ? mirror(virtual) : virtual,
                                   weight: size)
        }
    }

    static func fit(_ requested: [CGFloat], minimums: [CGFloat], total: CGFloat) -> [CGFloat] {
        guard requested.count == minimums.count, !requested.isEmpty,
              minimums.allSatisfy({ $0.isFinite && $0 >= 0 }),
              requested.allSatisfy({ $0.isFinite && $0 >= 0 }),
              minimums.reduce(0, +) <= total else { return requested }
        var result = requested
        var pinned = Set<Int>()
        while let short = result.indices.first(where: { !pinned.contains($0) && result[$0] + 0.5 < minimums[$0] }) {
            pinned.insert(short)
            let pinnedTotal = pinned.reduce(CGFloat.zero) { $0 + minimums[$1] }
            let free = result.indices.filter { !pinned.contains($0) }
            let freeRequested = free.reduce(CGFloat.zero) { $0 + requested[$1] }
            for index in pinned { result[index] = minimums[index] }
            let remaining = max(total - pinnedTotal, 0)
            for index in free { result[index] = freeRequested > 0 ? remaining * requested[index] / freeRequested : remaining / CGFloat(max(free.count, 1)) }
        }
        return result
    }
}
