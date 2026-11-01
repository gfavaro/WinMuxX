import AppKit

@MainActor
func pointerFocusCandidate(at point: CGPoint) -> Window? {
    let monitor = point.monitorApproximation
    guard monitor.visibleRect.contains(point) else { return nil }
    let workspace = monitor.activeWorkspace
    return workspace.floatingWindows.first {
        $0.participatesInWorkspaceFocus && !$0.isHiddenInCorner && $0.lastKnownActualRect?.contains(point) == true
    } ?? point.findIn(tree: workspace.rootTilingContainer, virtual: false)
        ?? workspace.floatingWindows.first { $0.participatesInWorkspaceFocus && $0.lastKnownActualRect == nil }
}

@MainActor
func pointerFocusTarget(at point: CGPoint, frontmostWindowId: UInt32?) -> Window? {
    let monitor = point.monitorApproximation
    guard monitor.visibleRect.contains(point), let id = frontmostWindowId,
          let window = Window.get(byId: id), window.nodeWorkspace === monitor.activeWorkspace,
          window.participatesInWorkspaceFocus, !window.isHiddenInCorner else { return nil }
    return window
}

/// Resolve native occlusion only after dwell, off MainActor. Pointer movement
/// uses cached model geometry and never enumerates native windows per event.
actor PointerFocusNativeHitTester {
    static let shared = PointerFocusNativeHitTester()

    func windowId(at point: CGPoint) -> UInt32? {
        guard !Task.isCancelled,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let ownPid = Int(ProcessInfo.processInfo.processIdentifier)
        for info in windows {
            // WinMuxX's own panels (dimming, borders, the pin line) sit over other windows.
            if (info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue == ownPid { continue }
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(point),
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0 else { continue }
            return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
        return nil
    }
}
