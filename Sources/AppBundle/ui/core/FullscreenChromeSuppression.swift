import CoreGraphics
import Foundation
import NativeSpaces

/// Displays showing native fullscreen content, by display UUID. WinMuxX chrome (sidebar,
/// borders, dimming) stays off them. Decided from what is on screen, not from the focused
/// window: a fullscreen video keeps covering its display while another app is focused.
/// After WinMux PR #31 by Ilya Kudravets.
@MainActor
var fullscreenContentDisplays: Set<String> = []

@MainActor
func updateNativeFullscreenChromeSuppression() {
    fullscreenContentDisplays = runtime.workspaceBackend.current.fullscreenDisplayIDs()
}

/// Native Spaces: a display whose showing Space is not an ordinary desktop.
func fullscreenNativeSpaceDisplays(_ displays: [NativeSpaceDisplay]) -> Set<String> {
    Set(displays.filter { display in
        display.spaces.first { $0.id == display.activeSpaceID }.map { !$0.isDesktop } ?? false
    }.map(\.identifier))
}

/// Virtual workspaces: the displays under a known fullscreen window that is on screen.
@MainActor
func fullscreenWindowDisplays(onScreen frames: [UInt32: CGRect]) -> Set<String> {
    let fullscreen = Workspace.all.compactMap(\.existingMacOsNativeFullscreenWindowsContainer)
        .flatMap { $0.children.filterIsInstance(of: Window.self) }.map(\.windowId)
    return Set(fullscreen.compactMap { id in
        frames[id].flatMap { frame in
            monitors.first { $0.rect.contains(CGPoint(x: frame.midX, y: frame.midY)) }?.displayUUID
        }
    })
}

func onScreenWindowFrames() -> [UInt32: CGRect] {
    let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var frames: [UInt32: CGRect] = [:]
    for row in rows {
        guard let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let bounds = row[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
        frames[id] = frame
    }
    return frames
}

@MainActor
func shouldSuppressChromeForFullscreenContent(on monitor: Monitor) -> Bool {
    monitor.displayUUID.map(fullscreenContentDisplays.contains) ?? false
}

@MainActor
func shouldSuppressWorkspaceSidebarForFullscreenContent(on monitor: Monitor) -> Bool {
    shouldSuppressChromeForFullscreenContent(on: monitor)
}
