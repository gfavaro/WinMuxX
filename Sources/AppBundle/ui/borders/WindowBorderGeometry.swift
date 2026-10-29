import AppKit
import SwiftUI

/// Separate edge surfaces must share a backing-pixel phase on screen, too.
/// Local pixel-aligned partitions alone still acquire seams when the compositor
/// samples each surface at a fractional screen origin. Preserve the path's size.
/// The window frame to draw a border around so the whole border stays on `display`
/// (top-left coordinates). A border edge that crossed a display edge was invisible
/// past it, and macOS could move that edge's window somewhere else entirely.
func windowBorderFrame(_ frame: CGRect, width: CGFloat, within display: CGRect?) -> CGRect {
    guard let display else { return frame }
    let outer = frame.insetBy(dx: -width, dy: -width).intersection(display)
    guard !outer.isNull, outer.width > width * 2, outer.height > width * 2 else { return frame }
    return outer.insetBy(dx: width, dy: width)
}

func pixelAlignedWindowBorderFrame(_ frame: CGRect, width: CGFloat, scale: CGFloat) -> CGRect {
    let scale = max(1, scale)
    let outer = frame.insetBy(dx: -width, dy: -width)
    return frame.offsetBy(
        dx: (outer.minX * scale).rounded() / scale - outer.minX,
        dy: (outer.minY * scale).rounded() / scale - outer.minY,
    )
}

/// Shared vector geometry; no full-window bitmap is allocated.
struct WindowBorderGeometry {
    struct Key: Equatable {
        let size: CGSize
        let radius: CGFloat
        let width: CGFloat
        let scale: CGFloat
        var bottomRadius: CGFloat? = nil
        var partitionRadius: CGFloat { max(radius, bottomRadius ?? radius) }
    }
    let key: Key
    let path: CGPath

    init(size: CGSize, radius: CGFloat, width: CGFloat, scale: CGFloat, bottomRadius: CGFloat? = nil) {
        key = Key(size: size, radius: radius, width: width, scale: scale, bottomRadius: bottomRadius)
        let bounds = CGRect(origin: .zero, size: size)
        let ring = CGMutablePath()
        ring.addPath(Self.outline(in: bounds, top: radius + width, bottom: (bottomRadius ?? radius) + width))
        // Close the antialiased fissure with at most half a backing pixel.
        let overlap = min(width, 0.5 / max(1, scale))
        let inner = bounds.insetBy(dx: width + overlap, dy: width + overlap)
        if !inner.isEmpty {
            ring.addPath(Self.outline(in: inner, top: max(0, radius - overlap),
                bottom: max(0, (bottomRadius ?? radius) - overlap)))
        }
        path = ring
    }

    private static func outline(in rect: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
        if top == bottom {
            return RoundedRectangle(cornerRadius: top, style: .continuous).path(in: rect).cgPath
        }
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous).path(in: rect).cgPath
    }
}
