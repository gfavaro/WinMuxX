import AppKit
import Common

struct WorkspaceGroupFrame {
    let node: TreeNode
    let physical: Rect
    let virtual: Rect
    let visibility: ScrollingColumnVisibility?
    let stackingIndex: Int
}

extension Workspace {
    /// Both rendering and directional navigation consume these workspace slots.
    /// Scrolling keeps logical columns distinct even when edge previews overlap.
    @MainActor
    func arrangementGroupFrames(in rect: Rect, gaps: ResolvedGaps) -> [WorkspaceGroupFrame] {
        let groups = workspaceLayoutUnits
        guard !groups.isEmpty else { return [] }
        switch arrangement {
            case .dwindle: return []
            case .scrolling:
                let geometry = scrollingGeometry(in: rect, gaps: gaps)
                scrollingOffset = geometry.clampedOffset
                // A pinned column sits at its edge, above the strip.
                let pinned = scrollingPinSplit(in: rect, gaps: gaps).flatMap { split in
                    pinnedScrollingColumn.map { WorkspaceGroupFrame(node: $0, physical: split.pinned, virtual: split.pinned,
                                                                   visibility: .visible, stackingIndex: geometry.columns.count) }
                }
                return zip(scrollingStripUnits, geometry.columns).map { node, frame in
                    WorkspaceGroupFrame(node: node,
                        physical: Rect(topLeftX: frame.physicalFrame.minX, topLeftY: frame.physicalFrame.minY,
                                       width: frame.physicalFrame.width, height: frame.physicalFrame.height),
                        virtual: Rect(topLeftX: frame.logicalFrame.minX, topLeftY: frame.logicalFrame.minY,
                                      width: frame.logicalFrame.width, height: frame.logicalFrame.height),
                        visibility: frame.visibility, stackingIndex: geometry.stackingOrder.firstIndex(of: frame.index) ?? frame.index)
                } + (pinned.map { [$0] } ?? [])
            case .master:
                let primary = masterGroupIndex
                guard groups.indices.contains(primary) else { return [] }
                if groups.count == 1 { return [.init(node: groups[primary], physical: rect, virtual: rect, visibility: nil, stackingIndex: 0)] }
                let axis = config.master.side.orientation
                let ratio = masterRatio.flatMap { $0.isFinite ? min(max($0, 0.1), 0.9) : nil } ?? CGFloat(config.master.size)
                let stack = groups.indices.filter { $0 != primary }.map { groups[$0] }
                let mainFrames = TileLayoutGeometry.calculate(TileLayoutInput(
                    origin: rect.topLeftCorner, size: rect.size, horizontal: axis == .h,
                    innerGap: CGFloat(gaps.inner.get(axis)), weights: [ratio, 1 - ratio],
                    minimumExtents: [groups[primary].minimumLayoutExtent(along: axis, gaps: gaps, rect: rect),
                        stack.map { $0.minimumLayoutExtent(along: axis, gaps: gaps, rect: rect) }.max() ?? 0],
                    master: true, reversed: config.master.side.isReversed))
                guard mainFrames.count == 2 else { return [] }
                var result = [WorkspaceGroupFrame(node: groups[primary], physical: mainFrames[0].physical.layoutRect,
                                                  virtual: mainFrames[0].virtual.layoutRect, visibility: nil, stackingIndex: 0)]
                let stackRect = mainFrames[1].physical.layoutRect
                let stackAxis = axis.opposite
                let stackFrames = TileLayoutGeometry.calculate(TileLayoutInput(
                    origin: stackRect.topLeftCorner, size: stackRect.size, horizontal: stackAxis == .h,
                    innerGap: CGFloat(gaps.inner.get(stackAxis)), weights: Array(repeating: 1, count: stack.count),
                    minimumExtents: stack.map { $0.minimumLayoutExtent(along: stackAxis, gaps: gaps, rect: stackRect) },
                    master: true, reversed: false))
                result += zip(stack, stackFrames).map { node, frame in
                    WorkspaceGroupFrame(node: node, physical: masterStackLayout == .stacked ? stackRect : frame.physical.layoutRect,
                                        virtual: frame.virtual.layoutRect, visibility: nil, stackingIndex: result.count)
                }
                return result
        }
    }
}

// TileLayoutGeometry already uses WinMuxX's top-left coordinate system.
// CGRect.toRect() is for AppKit coordinates and would move these slots down.
private extension CGRect {
    var layoutRect: Rect {
        Rect(topLeftX: minX, topLeftY: minY, width: width, height: height)
    }
}
