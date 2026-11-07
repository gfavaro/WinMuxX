import AppKit
import Common

struct WorkspaceGroupFrame {
    let node: TreeNode
    let physical: Rect
    let virtual: Rect
    let stackingIndex: Int
}

extension Workspace {
    /// Both rendering and directional navigation consume these workspace slots.
    @MainActor
    func arrangementGroupFrames(in rect: Rect, gaps: ResolvedGaps) -> [WorkspaceGroupFrame] {
        let groups = workspaceLayoutUnits
        guard !groups.isEmpty else { return [] }
        switch arrangement {
            // Tabbed shows one window at a time; layoutWorkspace places it under the tab bar.
            case .dwindle, .tabbed: return []
            case .master:
                let primary = masterGroupIndex
                guard groups.indices.contains(primary) else { return [] }
                if groups.count == 1 { return [.init(node: groups[primary], physical: rect, virtual: rect, stackingIndex: 0)] }
                let axis = config.master.side.orientation
                let stack = groups.indices.filter { $0 != primary }.map { groups[$0] }
                let ratio = masterRatio.flatMap { $0.isFinite ? min(max($0, 0.1), 0.9) : nil } ?? CGFloat(config.master.size)
                let mainFrames = TileLayoutGeometry.calculate(TileLayoutInput(
                    origin: rect.topLeftCorner, size: rect.size, horizontal: axis == .h,
                    innerGap: CGFloat(gaps.inner.get(axis)), weights: [ratio, 1 - ratio],
                    minimumExtents: [groups[primary].minimumLayoutExtent(along: axis, gaps: gaps, rect: rect),
                        stack.map { $0.minimumLayoutExtent(along: axis, gaps: gaps, rect: rect) }.max() ?? 0],
                    master: true, reversed: config.master.side.isReversed))
                guard mainFrames.count == 2 else { return [] }
                var result = [WorkspaceGroupFrame(node: groups[primary], physical: mainFrames[0].physical.layoutRect,
                                                  virtual: mainFrames[0].virtual.layoutRect, stackingIndex: 0)]
                let stackRect = mainFrames[1].physical.layoutRect
                let stackAxis = axis.opposite
                let stackFrames = TileLayoutGeometry.calculate(TileLayoutInput(
                    origin: stackRect.topLeftCorner, size: stackRect.size, horizontal: stackAxis == .h,
                    innerGap: CGFloat(gaps.inner.get(stackAxis)), weights: Array(repeating: 1, count: stack.count),
                    minimumExtents: stack.map { $0.minimumLayoutExtent(along: stackAxis, gaps: gaps, rect: stackRect) },
                    master: true, reversed: false))
                result += zip(stack, stackFrames).map { node, frame in
                    WorkspaceGroupFrame(node: node, physical: frame.physical.layoutRect,
                                        virtual: frame.virtual.layoutRect, stackingIndex: result.count)
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
