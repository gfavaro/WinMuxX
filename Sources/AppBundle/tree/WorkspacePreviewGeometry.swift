import Foundation

/// Translate saved desktop geometry, never the parking coordinates of an inactive workspace.
func normalizedWorkspacePreviewFrame(_ frame: CGRect, origin: CGPoint, desktopSize: CGSize, minimumVisibleSize: CGFloat = 2) -> CGRect? {
    guard desktopSize.width > 0, desktopSize.height > 0,
          [frame.minX, frame.minY, frame.width, frame.height, origin.x, origin.y,
           desktopSize.width, desktopSize.height].allSatisfy(\.isFinite), frame.width > 0, frame.height > 0 else { return nil }
    // Parked windows retain only a one-pixel strip at a bottom corner. A cold
    // registration must not replace a restored preview with that strip.
    let visible = frame.intersection(CGRect(origin: origin, size: desktopSize))
    guard visible.width > minimumVisibleSize, visible.height > minimumVisibleSize else { return nil }
    return CGRect(x: (frame.minX - origin.x) / desktopSize.width,
                  y: (frame.minY - origin.y) / desktopSize.height,
                  width: frame.width / desktopSize.width, height: frame.height / desktopSize.height)
}

