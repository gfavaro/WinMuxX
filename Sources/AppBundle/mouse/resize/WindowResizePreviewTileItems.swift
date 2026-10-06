import AppKit
import Common

@MainActor
func windowResizePreviewTileItems(
    container: TilingContainer,
    point: CGPoint,
    width: CGFloat,
    height: CGFloat,
    virtual: Rect,
    context: WindowResizePreviewLayoutContext,
    activeWindowId: UInt32?,
) -> [WindowResizePreviewItem] {
    let rect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
    let frames = container.tileChildFrames(in: rect, gaps: context.resolvedGaps) {
        context.weight(for: $0, orientation: container.orientation)
    }
    return zip(container.children, frames).flatMap { child, frame in
        let childVirtual = Rect(topLeftX: frame.virtual.topLeftX + virtual.topLeftX - point.x,
            topLeftY: frame.virtual.topLeftY + virtual.topLeftY - point.y,
            width: frame.virtual.width, height: frame.virtual.height)
        return windowResizePreviewItems(node: child, point: frame.physical.topLeftCorner,
            width: frame.physical.width, height: frame.physical.height, virtual: childVirtual,
            context: context, activeWindowId: activeWindowId)
    }
}
