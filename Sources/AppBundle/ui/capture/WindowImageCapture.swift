import CoreGraphics
import ScreenCaptureKit

/// Images of windows and of the screen, through ScreenCaptureKit, at one pixel per point.
enum WindowImageCapture {
    /// The windows that can be captured now, by window id. Fetch once per render and reuse it.
    static func windows() async throws -> [UInt32: SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// `window` by itself, without its shadow, scaled to fit `size` (its own size by default).
    static func image(of window: SCWindow, size: CGSize? = nil) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        let target = size ?? window.frame.size
        configuration.width = max(1, Int(target.width.rounded()))
        configuration.height = max(1, Int(target.height.rounded()))
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .nominal
        configuration.includeChildWindows = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                          configuration: configuration)
    }

    /// What the screen shows in `rect` (global coordinates, top-left origin), leaving out the
    /// windows in `excluding`, and WinMuxX's own panels with `excludingOwnPanels`. Nil when no
    /// display holds the rect's centre.
    static func image(of rect: CGRect, excluding: [UInt32] = [], excludingOwnPanels: Bool = false) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) else { return nil }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let excluded = content.windows.filter {
            excluding.contains($0.windowID) || excludingOwnPanels && $0.owningApplication?.processID == ownProcess
        }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        configuration.width = max(1, Int(rect.width.rounded()))
        configuration.height = max(1, Int(rect.height.rounded()))
        configuration.showsCursor = false
        configuration.captureResolution = .nominal
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: excluded), configuration: configuration)
    }
}
