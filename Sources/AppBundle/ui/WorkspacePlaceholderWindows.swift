import AppKit

// Without Screen Recording, previews and animations draw each window as a card with its
// app's icon: macOS does not let WinMuxX read another app's window contents.

@MainActor private var placeholderIconsByPid: [pid_t: CGImage] = [:]

@MainActor
func placeholderAppIcon(forWindowId id: UInt32) -> CGImage? {
    guard let app = MacWindow.allWindowsMap[id]?.macApp.nativeApplication else { return nil }
    let pid = app.processIdentifier
    if let icon = placeholderIconsByPid[pid] { return icon }
    var rect = CGRect(x: 0, y: 0, width: 128, height: 128)
    guard let icon = app.icon?.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
    if placeholderIconsByPid.count >= 64 { placeholderIconsByPid.removeAll() }
    placeholderIconsByPid[pid] = icon
    return icon
}

/// `frame` is in the context's bottom-left coordinates.
func drawWindowPlaceholder(_ frame: CGRect, icon: CGImage?, in context: CGContext) {
    guard frame.width > 0, frame.height > 0 else { return }
    let radius = min(16, frame.width / 8, frame.height / 8)
    let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(path)
    context.setFillColor(CGColor(gray: 0.18, alpha: 0.94))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    context.setLineWidth(1)
    context.strokePath()
    let side = min(96, frame.width * 0.35, frame.height * 0.35)
    if let icon, side >= 16 {
        context.interpolationQuality = .high
        context.draw(icon, in: CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side))
    }
    context.restoreGState()
}

/// A tab flip's faces and backdrop without capture: two cards over the display's wallpaper.
@MainActor
func placeholderWindowFlipImages(front: UInt32, back: UInt32, rect: Rect, padding: CGFloat, monitor: Monitor) -> WindowFlipImages? {
    let size = CGSize(width: rect.width, height: rect.height)
    let scale = min(1, 1600 / max(size.width, size.height, 1))
    func card(_ id: UInt32) -> CGImage? {
        guard let context = placeholderContext(width: size.width * scale, height: size.height * scale) else { return nil }
        context.scaleBy(x: scale, y: scale)
        drawWindowPlaceholder(CGRect(origin: .zero, size: size), icon: placeholderAppIcon(forWindowId: id), in: context)
        return context.makeImage()
    }
    let outer = CGRect(x: rect.topLeftX - padding, y: rect.topLeftY - padding,
                       width: rect.width + 2 * padding, height: rect.height + 2 * padding)
    guard let first = card(front), let second = card(back),
          let context = placeholderContext(width: outer.width * scale, height: outer.height * scale) else { return nil }
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(CGColor(gray: 0.12, alpha: 1))
    context.fill(CGRect(origin: .zero, size: outer.size))
    let screens = NSScreen.screens
    let index = monitor.monitorAppKitNsScreenScreensId - 1
    if screens.indices.contains(index), let url = NSWorkspace.shared.desktopImageURL(for: screens[index]),
       let source = CGImageSourceCreateWithURL(url as CFURL, nil),
       let wallpaper = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                    kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) {
        // Aspect-fill the display, then place it so the backdrop shows the part behind the window.
        let display = monitor.rect
        let ratio = max(display.width / Double(wallpaper.width), display.height / Double(wallpaper.height))
        let filled = CGSize(width: Double(wallpaper.width) * ratio, height: Double(wallpaper.height) * ratio)
        let originX = display.minX + (display.width - filled.width) / 2 - outer.minX
        let topY = display.minY + (display.height - filled.height) / 2 - outer.minY
        context.draw(wallpaper, in: CGRect(x: originX, y: outer.height - topY - filled.height, width: filled.width, height: filled.height))
    }
    guard let background = context.makeImage() else { return nil }
    return WindowFlipImages(front: first, back: second, background: background)
}

private func placeholderContext(width: CGFloat, height: CGFloat) -> CGContext? {
    CGContext(data: nil, width: max(1, Int(width)), height: max(1, Int(height)), bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
}
