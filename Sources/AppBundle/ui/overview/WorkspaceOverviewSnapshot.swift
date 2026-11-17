import AppKit
import Common
import ImageIO

/// A workspace drawn for the overview: its wallpaper, and each window as a card with its app's
/// icon. Only immutable values cross to the renderer; AX objects and trees stay on MainActor.
struct WorkspaceSnapshotRequest: Sendable {
    struct Window: Sendable {
        let id: UInt32
        let frame: CGRect
        var icon: CGImage? = nil
    }
    var key: WorkspaceSnapshotKey
    var wallpaper: URL? = nil
    var windows: [Window] = []
    var maximumPixelSize: CGSize = CGSize(width: 2048, height: 2048)
    var windowsAreBackToFront = false
}

struct WorkspaceSnapshotKey: Hashable, Sendable {
    let workspace: WorkspaceId
    let display: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(workspace: WorkspaceId, display: String, rect: CGRect) {
        self.workspace = workspace; self.display = display
        x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
    }
}

/// Each window's place in the native stacking order, front first.
func workspaceWindowRanks() -> [UInt32: Int] {
    let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    return Dictionary(info.enumerated().compactMap { index, item in
        (item[kCGWindowNumber as String] as? UInt32).map { ($0, index) }
    }, uniquingKeysWith: { first, _ in first })
}

/// Draws `request` off the main thread: the wallpaper filling the area, then the window cards
/// back to front.
func renderWorkspaceSnapshot(_ request: WorkspaceSnapshotRequest) throws -> CGImage {
    let width = request.key.width, height = request.key.height
    let scale = min(1, request.maximumPixelSize.width / width, request.maximumPixelSize.height / height)
    guard width > 0, height > 0,
          let context = CGContext(data: nil, width: max(1, Int(width * scale)), height: max(1, Int(height * scale)),
              bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CocoaError(.coderInvalidValue)
    }
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(CGColor(gray: 0.12, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if let url = request.wallpaper, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
       let wallpaper = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                    kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) {
        let ratio = max(width / Double(wallpaper.width), height / Double(wallpaper.height))
        let size = CGSize(width: Double(wallpaper.width) * ratio, height: Double(wallpaper.height) * ratio)
        context.draw(wallpaper, in: CGRect(x: (width - size.width) / 2, y: (height - size.height) / 2, width: size.width, height: size.height))
    }
    var windows = request.windows
    if windows.count > 1 && !request.windowsAreBackToFront {
        let rank = workspaceWindowRanks()
        windows.sort { (rank[$0.id] ?? 0) > (rank[$1.id] ?? 0) }
    }
    for window in windows { drawWindowPlaceholder(window.frame, icon: window.icon, in: context) }
    guard let image = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
    return image
}
