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

/// Virtual workspaces: the known native fullscreen windows.
@MainActor
func nativeFullscreenWindowIds() -> [UInt32] {
    Workspace.all.compactMap(\.existingMacOsNativeFullscreenWindowsContainer)
        .flatMap { $0.children.filterIsInstance(of: Window.self) }.map(\.windowId)
}

/// Virtual workspaces: the displays under a known fullscreen window that is on screen.
@MainActor
func fullscreenWindowDisplays(onScreen frames: [UInt32: CGRect]) -> Set<String> {
    Set(nativeFullscreenWindowIds().compactMap { id in
        frames[id].flatMap { frame in
            monitors.first { $0.rect.contains(CGPoint(x: frame.midX, y: frame.midY)) }?.displayUUID
        }
    })
}

/// The on-screen frames of just these windows. WindowServer describes only the windows
/// asked about rather than every window on screen.
func onScreenWindowFrames(_ ids: [UInt32]) -> [UInt32: CGRect] {
    var frames: [UInt32: CGRect] = [:]
    for row in windowDescriptions(ids) where (row[kCGWindowIsOnscreen as String] as? Bool) == true {
        guard let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let bounds = row[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
        frames[id] = frame
    }
    return frames
}

/// WindowServer's description of just these windows, on screen or not. Windows that no
/// longer exist are left out.
func windowDescriptions(_ ids: [UInt32]) -> [[String: Any]] {
    guard !ids.isEmpty else { return [] }
    // The array holds the window numbers themselves, not objects.
    var numbers = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
    guard let array = CFArrayCreate(nil, &numbers, numbers.count, nil) else { return [] }
    return CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] ?? []
}

@MainActor
func shouldSuppressChromeForFullscreenContent(on monitor: Monitor) -> Bool {
    monitor.displayUUID.map(fullscreenContentDisplays.contains) ?? false
}

@MainActor
func shouldSuppressWorkspaceSidebarForFullscreenContent(on monitor: Monitor) -> Bool {
    shouldSuppressChromeForFullscreenContent(on: monitor)
}
