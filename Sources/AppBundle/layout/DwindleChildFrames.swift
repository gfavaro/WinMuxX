import AppKit
import Common

extension TilingContainer {
    @MainActor
    func dwindleMinimumExtent(children: ArraySlice<TreeNode>, along axis: Orientation, rect: Rect, gaps: ResolvedGaps, ratioAt: ((Int) -> CGFloat)? = nil) -> CGFloat {
        let snapshots = children.map(makeLayoutMinimumSnapshot)
        let ratios = (0..<max(children.count - 1, 0)).map { index in
            ratioAt?(children.startIndex + index) ?? dwindleSplitRatio(at: children.startIndex + index)
        }
        let settings = DwindleMinimumSettings(orientationHorizontal: dwindleOrientation.map { $0 == .h },
            explicitShares: isExplicitDwindle ? frameDwindleShares : nil, ratios: ratios)
        let node = LayoutMinimumSnapshot.container(layout: .dwindle, horizontal: orientation == .h,
            children: snapshots, dwindle: settings, tabChrome: .zero, stackedPadding: 0)
        let extent = node.extent(horizontal: axis == .h,
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height),
            gap: CGSize(width: CGFloat(gaps.inner.horizontal.toDouble()), height: CGFloat(gaps.inner.vertical.toDouble())))
        return extent
    }

    @MainActor
    func dwindleChildFrames(in rect: Rect, gaps: ResolvedGaps, ratioAt: ((Int) -> CGFloat)? = nil, enforceMinimums: Bool = true) -> [Rect] {
        let children = frameLayoutChildren
        var shares = frameDwindleShares
        if let ratioAt, var explicit = shares, explicit.count > 1 {
            for index in 0..<(explicit.count - 1) {
                let ratio = ratioAt(index)
                if ratio != dwindleSplitRatio(at: index) {
                    let total = explicit[index] + explicit[index + 1]
                    explicit[index] = total * ratio
                    explicit[index + 1] = total - explicit[index]
                }
            }
            shares = explicit
        }
        let ratios = (0..<max(children.count - 1, 0)).map { ratioAt?($0) ?? dwindleSplitRatio(at: $0) }
        let input = DwindleLayoutInput(origin: rect.topLeftCorner, size: rect.size,
            horizontalGap: CGFloat(gaps.inner.horizontal.toDouble()), verticalGap: CGFloat(gaps.inner.vertical.toDouble()),
            children: children.map(makeLayoutMinimumSnapshot),
            orientationHorizontal: dwindleOrientation.map { $0 == .h }, explicitShares: shares,
            ratios: ratios, enforceMinimums: enforceMinimums)
        return DwindleLayoutGeometry.calculate(input).map { Rect(topLeftX: $0.minX, topLeftY: $0.minY, width: $0.width, height: $0.height) }
    }
}

@MainActor
private func makeLayoutMinimumSnapshot(_ node: TreeNode) -> LayoutMinimumSnapshot {
    switch node.nodeCases {
    case .window(let window): return .window(window.minimumLayoutSize)
    case .tilingContainer(let container):
        let children = container.frameLayoutChildren
        let chrome = container.layout == .tabGroup && container.showsWindowTabs
            ? CGSize(width: 2 * windowTabGroupShellHorizontalInset(),
                     height: resolvedWindowTabBarHeight() + windowTabGroupShellTopInset() + windowTabGroupShellBottomInset())
            : .zero
        let dwindle = container.layout == .dwindle
            ? DwindleMinimumSettings(orientationHorizontal: container.dwindleOrientation.map { $0 == .h },
                explicitShares: container.frameDwindleShares,
                ratios: (0..<max(children.count - 1, 0)).map { container.dwindleSplitRatio(at: $0) })
            : nil
        return .container(layout: container.layout, horizontal: container.orientation == .h,
            children: children.map(makeLayoutMinimumSnapshot), dwindle: dwindle,
            tabChrome: chrome, stackedPadding: CGFloat(max(config.tabGroupPadding, 0)))
    default: return .window(.zero)
    }
}

@MainActor
func fittedDwindleSplitLength(total: CGFloat, gap: CGFloat, ratio: CGFloat, minimum: CGFloat, remainingMinimum: CGFloat) -> CGFloat {
    let available = max(total - gap, 0)
    let requested = available * ratio
    return fitLayoutSizes([requested, available - requested], minimums: [minimum, remainingMinimum], total: available)[0]
}
