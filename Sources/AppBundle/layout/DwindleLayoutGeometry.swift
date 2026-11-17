import CoreGraphics

/// A value-only description of the minimum size behavior of one tree node.
indirect enum LayoutMinimumSnapshot {
    case window(CGSize)
    case container(layout: Layout, horizontal: Bool, children: [LayoutMinimumSnapshot],
                   dwindle: DwindleMinimumSettings?, tabChrome: CGSize)

    func extent(horizontal: Bool, in rect: CGRect, gap: CGSize) -> CGFloat {
        switch self {
        case .window(let size): return horizontal ? size.width : size.height
        case .container(let layout, let orientationHorizontal, let children, let dwindle, let chrome):
            guard !children.isEmpty else { return 0 }
            if layout == .dwindle, let dwindle {
                return Self.dwindleExtent(children: children, settings: dwindle, axisHorizontal: horizontal, rect: rect, gap: gap)
            }
            let values = children.map { $0.extent(horizontal: horizontal, in: rect, gap: gap) }
            if layout == .tabGroup { return (values.max() ?? 0) + (horizontal ? chrome.width : chrome.height) }
            return orientationHorizontal == horizontal
                ? values.reduce(0, +) + (horizontal ? gap.width : gap.height) * CGFloat(max(values.count - 1, 0))
                : values.max() ?? 0
        }
    }

    /// A Dwindle split lays its children side by side along its axis, by their shares.
    private static func dwindleExtent(children: [LayoutMinimumSnapshot], settings: DwindleMinimumSettings,
                                      axisHorizontal: Bool, rect: CGRect, gap: CGSize) -> CGFloat {
        let splitHorizontal = settings.orientationHorizontal ?? (rect.width >= rect.height)
        let values = children.map { $0.extent(horizontal: axisHorizontal, in: rect, gap: gap) }
        return splitHorizontal == axisHorizontal
            ? values.reduce(0, +) + CGFloat(max(values.count - 1, 0)) * (splitHorizontal ? gap.width : gap.height)
            : values.max() ?? 0
    }
}

struct DwindleMinimumSettings {
    /// nil chooses the axis from the area's shape.
    let orientationHorizontal: Bool?
}

struct DwindleLayoutInput {
    let origin: CGPoint
    let size: CGSize
    let horizontalGap: CGFloat
    let verticalGap: CGFloat
    let children: [LayoutMinimumSnapshot]
    let orientationHorizontal: Bool?
    let shares: [CGFloat]
    let enforceMinimums: Bool
}

enum DwindleLayoutGeometry {
    static func calculate(_ input: DwindleLayoutInput) -> [CGRect] {
        guard !input.children.isEmpty else { return [] }
        let gapSize = CGSize(width: input.horizontalGap, height: input.verticalGap)
        let shares = input.shares
        let splitHorizontal = input.orientationHorizontal ?? (input.size.width >= input.size.height)
        let splitGap = splitHorizontal ? gapSize.width : gapSize.height
        let extent = splitHorizontal ? input.size.width : input.size.height
        let available = max(extent - CGFloat(max(shares.count - 1, 0)) * splitGap, 0)
        let requested = shares.map { $0 * available }
        // Each child's minimum is measured in the area it is given: a nested split picks its axis
        // from that area's shape.
        let minimums = zip(input.children, requested).map { child, length in
            child.extent(horizontal: splitHorizontal, in: CGRect(origin: input.origin,
                size: splitHorizontal ? CGSize(width: length, height: input.size.height) : CGSize(width: input.size.width, height: length)),
                gap: gapSize)
        }
        let sizes = input.enforceMinimums ? TileLayoutGeometry.fit(requested, minimums: minimums, total: available) : requested
        var point = input.origin
        return sizes.map { size in
            let frame = CGRect(x: point.x, y: point.y, width: splitHorizontal ? size : input.size.width,
                               height: splitHorizontal ? input.size.height : size)
            if splitHorizontal { point.x += size + splitGap } else { point.y += size + splitGap }
            return frame
        }
    }
}
