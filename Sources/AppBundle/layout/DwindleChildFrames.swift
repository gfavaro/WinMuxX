import AppKit
import Common

extension TilingContainer {
    @MainActor
    func dwindleMinimumExtent(children: ArraySlice<TreeNode>, along axis: Orientation, rect: Rect, gaps: ResolvedGaps, ratioAt: ((Int) -> CGFloat)? = nil) -> CGFloat {
        if isExplicitDwindle {
            let splitAxis = dwindleAxis(width: rect.width, height: rect.height)
            let minimums = children.map { $0.minimumLayoutExtent(along: axis, gaps: gaps, rect: rect) }
            return splitAxis == axis
                ? minimums.reduce(0, +) + CGFloat(max(children.count - 1, 0)) * CGFloat(gaps.inner.get(axis).toDouble())
                : minimums.max() ?? 0
        }
        guard let child = children.first else { return 0 }
        guard children.count > 1 else { return child.minimumLayoutExtent(along: axis, gaps: gaps, rect: rect) }
        let splitAxis = dwindleAxis(width: rect.width, height: rect.height)
        let gap = CGFloat(gaps.inner.get(splitAxis).toDouble())
        let ratio = ratioAt?(children.startIndex) ?? dwindleSplitRatio(at: children.startIndex)
        let childRect = Rect(topLeftX: rect.topLeftX, topLeftY: rect.topLeftY,
            width: splitAxis == .h ? max(rect.width - gap, 0) * ratio : rect.width,
            height: splitAxis == .v ? max(rect.height - gap, 0) * ratio : rect.height)
        let minimum = child.minimumLayoutExtent(along: axis, gaps: gaps, rect: childRect)
        let tailRect = Rect(topLeftX: rect.topLeftX, topLeftY: rect.topLeftY,
            width: splitAxis == .h ? max(rect.width - gap, 0) * (1 - ratio) : rect.width,
            height: splitAxis == .v ? max(rect.height - gap, 0) * (1 - ratio) : rect.height)
        let tail = dwindleMinimumExtent(children: children.dropFirst(), along: axis, rect: tailRect, gaps: gaps, ratioAt: ratioAt)
        return splitAxis == axis ? minimum + gap + tail : max(minimum, tail)
    }

    @MainActor
    func dwindleChildFrames(in rect: Rect, gaps: ResolvedGaps, ratioAt: ((Int) -> CGFloat)? = nil, enforceMinimums: Bool = true) -> [Rect] {
        if isExplicitDwindle {
            let axis = dwindleAxis(width: rect.width, height: rect.height)
            let gap = CGFloat(gaps.inner.get(axis).toDouble())
            let available = max(rect.getDimension(axis) - CGFloat(max(children.count - 1, 0)) * gap, 0)
            var shares = dwindleShares(count: children.count)
            if let ratioAt, shares.count > 1 {
                for index in 0..<(shares.count - 1) {
                    let ratio = ratioAt(index)
                    if ratio != dwindleSplitRatio(at: index) {
                        let total = shares[index] + shares[index + 1]
                        shares[index] = total * ratio
                        shares[index + 1] = total - shares[index]
                    }
                }
            }
            let requested = shares.map { $0 * available }
            let sizes = enforceMinimums ? fitLayoutSizes(requested, minimums: children.map {
                $0.minimumLayoutExtent(along: axis, gaps: gaps, rect: rect)
            }, total: available) : requested
            var point = rect.topLeftCorner
            return sizes.map { size in
                defer { point = point.addingOffset(axis, size + gap) }
                return Rect(topLeftX: point.x, topLeftY: point.y,
                    width: axis == .h ? size : rect.width, height: axis == .v ? size : rect.height)
            }
        }
        var point = rect.topLeftCorner
        var width = rect.width
        var height = rect.height
        var frames: [Rect] = []
        for (index, child) in children.enumerated() {
            let last = index == children.indices.last
            let axis: Orientation = dwindleAxis(width: width, height: height)
            let length = axis == .h ? width : height
            let gap = last ? 0 : CGFloat(gaps.inner.get(axis).toDouble())
            let ratio = ratioAt?(index) ?? dwindleSplitRatio(at: index)
            var childLength = last ? length : max(length - gap, 0) * ratio
            if !last && enforceMinimums {
                // A nested automatic split can change axis when a minimum adjusts its
                // rectangle. Re-evaluate using the proposed child and remainder geometry.
                for _ in 0..<3 {
                    let childRect = Rect(topLeftX: point.x, topLeftY: point.y,
                        width: axis == .h ? childLength : width, height: axis == .v ? childLength : height)
                    let tailLength = max(length - gap - childLength, 0)
                    let tailRect = Rect(topLeftX: point.x, topLeftY: point.y,
                        width: axis == .h ? tailLength : width, height: axis == .v ? tailLength : height)
                    let remainingMinimum = dwindleMinimumExtent(children: children.dropFirst(index + 1),
                        along: axis, rect: tailRect, gaps: gaps, ratioAt: ratioAt)
                    let fitted = fittedDwindleSplitLength(total: length, gap: gap, ratio: ratio,
                        minimum: child.minimumLayoutExtent(along: axis, gaps: gaps, rect: childRect),
                        remainingMinimum: remainingMinimum)
                    if abs(fitted - childLength) < 0.001 { break }
                    childLength = fitted
                }
            }
            let childWidth = axis == .h ? childLength : width
            let childHeight = axis == .v ? childLength : height
            frames.append(Rect(topLeftX: point.x, topLeftY: point.y, width: childWidth, height: childHeight))
            let consumed = childLength + gap
            point = point.addingOffset(axis, consumed)
            if axis == .h { width = max(width - consumed, 0) }
            else { height = max(height - consumed, 0) }
        }
        return frames
    }
}

@MainActor
func fittedDwindleSplitLength(total: CGFloat, gap: CGFloat, ratio: CGFloat, minimum: CGFloat, remainingMinimum: CGFloat) -> CGFloat {
    let available = max(total - gap, 0)
    let requested = available * ratio
    return fitLayoutSizes([requested, available - requested], minimums: [minimum, remainingMinimum], total: available)[0]
}
