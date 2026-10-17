import AppKit
import SwiftUI

/// Shared vector geometry; no full-window bitmap is allocated.
struct WindowBorderGeometry {
    struct Key: Equatable {
        let size: CGSize
        let radius: CGFloat
        let width: CGFloat
        let scale: CGFloat
    }
    let key: Key
    let path: CGPath

    init(size: CGSize, radius: CGFloat, width: CGFloat, scale: CGFloat) {
        key = Key(size: size, radius: radius, width: width, scale: scale)
        let bounds = CGRect(origin: .zero, size: size)
        let ring = CGMutablePath()
        ring.addPath(RoundedRectangle(cornerRadius: radius + width, style: .continuous).path(in: bounds).cgPath)
        // Close the antialiased fissure with at most half a backing pixel.
        let overlap = min(width, 0.5 / max(1, scale))
        let inner = bounds.insetBy(dx: width + overlap, dy: width + overlap)
        if !inner.isEmpty {
            ring.addPath(RoundedRectangle(cornerRadius: max(0, radius - overlap), style: .continuous).path(in: inner).cgPath)
        }
        path = ring
    }
}
