import AppKit
import SwiftUI

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
