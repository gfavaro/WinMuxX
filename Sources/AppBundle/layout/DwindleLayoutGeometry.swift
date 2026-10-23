import CoreGraphics

/// A value-only description of the minimum size behavior of one tree node.
indirect enum LayoutMinimumSnapshot {
    case window(CGSize)
    case container(layout: Layout, horizontal: Bool, children: [LayoutMinimumSnapshot],
                   dwindle: DwindleMinimumSettings?, tabChrome: CGSize, stackedPadding: CGFloat)

    func extent(horizontal: Bool, in rect: CGRect, gap: CGSize) -> CGFloat {
        switch self {
        case .window(let size): return horizontal ? size.width : size.height
        case .container(let layout, let orientationHorizontal, let children, let dwindle, let chrome, let padding):
            guard !children.isEmpty else { return 0 }
            if layout == .dwindle, let dwindle {
                return Self.dwindleExtent(children: children, settings: dwindle, axisHorizontal: horizontal, rect: rect, gap: gap)
            }
            let values = children.map { $0.extent(horizontal: horizontal, in: rect, gap: gap) }
            if layout == .tabGroup { return (values.max() ?? 0) + (horizontal ? chrome.width : chrome.height) }
            if layout == .stacked {
                return (values.max() ?? 0) + (orientationHorizontal == horizontal && values.count > 1 ? padding * 2 : 0)
            }
            return orientationHorizontal == horizontal
                ? values.reduce(0, +) + (horizontal ? gap.width : gap.height) * CGFloat(max(values.count - 1, 0))
                : values.max() ?? 0
        }
    }

    private static func dwindleExtent(children: [LayoutMinimumSnapshot], settings: DwindleMinimumSettings,
                                      axisHorizontal: Bool, rect: CGRect, gap: CGSize) -> CGFloat {
        guard let first = children.first else { return 0 }
        let splitHorizontal = settings.orientationHorizontal ?? (rect.width >= rect.height)
        if settings.explicitShares != nil {
            let values = children.map { $0.extent(horizontal: axisHorizontal, in: rect, gap: gap) }
            return splitHorizontal == axisHorizontal
                ? values.reduce(0, +) + CGFloat(max(values.count - 1, 0)) * (splitHorizontal ? gap.width : gap.height)
                : values.max() ?? 0
        }
        guard children.count > 1 else { return first.extent(horizontal: axisHorizontal, in: rect, gap: gap) }
        let ratio = settings.ratios.first ?? 0.5
        let splitGap = splitHorizontal ? gap.width : gap.height
        let firstLength = max((splitHorizontal ? rect.width : rect.height) - splitGap, 0) * ratio
        let firstRect = CGRect(x: rect.minX, y: rect.minY,
            width: splitHorizontal ? firstLength : rect.width,
            height: splitHorizontal ? rect.height : firstLength)
        let tailLength = max((splitHorizontal ? rect.width : rect.height) - splitGap - firstLength, 0)
        let tailRect = CGRect(x: rect.minX, y: rect.minY,
            width: splitHorizontal ? tailLength : rect.width,
            height: splitHorizontal ? rect.height : tailLength)
        let firstMinimum = first.extent(horizontal: axisHorizontal, in: firstRect, gap: gap)
        let tail = LayoutMinimumSnapshot.container(layout: .dwindle, horizontal: settings.orientationHorizontal ?? splitHorizontal,
            children: Array(children.dropFirst()), dwindle: settings.droppingFirstRatio,
            tabChrome: .zero, stackedPadding: 0).extent(horizontal: axisHorizontal, in: tailRect, gap: gap)
        return splitHorizontal == axisHorizontal ? firstMinimum + splitGap + tail : max(firstMinimum, tail)
    }
}

struct DwindleMinimumSettings {
    let orientationHorizontal: Bool?
    let explicitShares: [CGFloat]?
    let ratios: [CGFloat]
    var droppingFirstRatio: DwindleMinimumSettings {
        DwindleMinimumSettings(orientationHorizontal: orientationHorizontal, explicitShares: nil,
                               ratios: Array(ratios.dropFirst()))
    }
}

struct DwindleLayoutInput {
    let origin: CGPoint
    let size: CGSize
    let horizontalGap: CGFloat
    let verticalGap: CGFloat
    let children: [LayoutMinimumSnapshot]
    let orientationHorizontal: Bool?
    let explicitShares: [CGFloat]?
    let ratios: [CGFloat]
    let enforceMinimums: Bool
}

enum DwindleLayoutGeometry {
    static func calculate(_ input: DwindleLayoutInput) -> [CGRect] {
        guard !input.children.isEmpty else { return [] }
        let gapSize = CGSize(width: input.horizontalGap, height: input.verticalGap)
        if let shares = input.explicitShares {
            let splitHorizontal = input.orientationHorizontal ?? (input.size.width >= input.size.height)
            let splitGap = splitHorizontal ? gapSize.width : gapSize.height
            let extent = splitHorizontal ? input.size.width : input.size.height
            let available = max(extent - CGFloat(max(shares.count - 1, 0)) * splitGap, 0)
            let requested = shares.map { $0 * available }
            let minimums = input.children.map { $0.extent(horizontal: splitHorizontal,
                in: CGRect(origin: input.origin, size: input.size), gap: gapSize) }
            let sizes = input.enforceMinimums ? TileLayoutGeometry.fit(requested, minimums: minimums, total: available) : requested
            var point = input.origin
            return sizes.map { size in
                let frame = CGRect(x: point.x, y: point.y, width: splitHorizontal ? size : input.size.width,
                                   height: splitHorizontal ? input.size.height : size)
                if splitHorizontal { point.x += size + splitGap } else { point.y += size + splitGap }
                return frame
            }
        }
        var point = input.origin
        var width = input.size.width, height = input.size.height
        var frames: [CGRect] = []
        for (index, child) in input.children.enumerated() {
            let last = index == input.children.count - 1
            let horizontal = input.orientationHorizontal ?? (width >= height)
            let length = horizontal ? width : height
            let splitGap = last ? 0 : (horizontal ? gapSize.width : gapSize.height)
            let ratio = input.ratios.indices.contains(index) ? input.ratios[index] : 0.5
            var childLength = last ? length : max(length - splitGap, 0) * ratio
            if !last && input.enforceMinimums {
                for _ in 0..<3 {
                    let childRect = CGRect(x: point.x, y: point.y, width: horizontal ? childLength : width,
                                           height: horizontal ? height : childLength)
                    let tailLength = max(length - splitGap - childLength, 0)
                    let tailRect = CGRect(x: point.x, y: point.y, width: horizontal ? tailLength : width,
                                          height: horizontal ? height : tailLength)
                    let remaining = LayoutMinimumSnapshot.container(layout: .dwindle,
                        horizontal: input.orientationHorizontal ?? horizontal,
                        children: Array(input.children.dropFirst(index + 1)),
                        dwindle: DwindleMinimumSettings(orientationHorizontal: input.orientationHorizontal,
                            explicitShares: nil, ratios: Array(input.ratios.dropFirst(index + 1))),
                        tabChrome: .zero, stackedPadding: 0).extent(horizontal: horizontal, in: tailRect, gap: gapSize)
                    let minimum = child.extent(horizontal: horizontal, in: childRect, gap: gapSize)
                    let available = max(length - splitGap, 0)
                    let requested = available * ratio
                    let fitted = TileLayoutGeometry.fit([requested, available - requested],
                        minimums: [minimum, remaining], total: available)[0]
                    if abs(fitted - childLength) < 0.001 { break }
                    childLength = fitted
                }
            }
            frames.append(CGRect(x: point.x, y: point.y, width: horizontal ? childLength : width,
                                 height: horizontal ? height : childLength))
            let consumed = childLength + splitGap
            if horizontal { point.x += consumed; width = max(width - consumed, 0) }
            else { point.y += consumed; height = max(height - consumed, 0) }
        }
        return frames
    }
}
