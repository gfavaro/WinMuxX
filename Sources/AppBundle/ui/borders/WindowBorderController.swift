import AppKit
import Common
import PrivateApi

@MainActor
final class WindowBorderController {
    static let shared = WindowBorderController()
    private var borders: [UInt32: WindowBorder] = [:]
    private var missionControlState = MissionControlBorderState()
    var isMissionControlActive: Bool { missionControlState.active }
    private(set) var missionControlWindowIds = Set<UInt32>()

    func startMissionControlMonitoring() {
        guard !isUnitTest else { return }
        if !winmux_watch_mission_control({ event, windowId in
            Task { @MainActor in
                let controller = WindowBorderController.shared
                // Our own reshape/order notifications cannot change Mission Control.
                // Scanning every border transaction creates a geometry feedback storm.
                if controller.borders.values.contains(where: { $0.windowId == windowId && windowId != 0 }) { return }
                if !controller.missionControlState.active,
                   [UInt32(723), 806, 807, 808].contains(event),
                   WindowMotion.shared.isAnimating(windowId) {
                    controller.refreshMovingBorder(windowId)
                    return
                }
                controller.missionControlChanged()
                // Native geometry/reorder events finish the overview animation
                // even when AX doesn't report its intermediate/final frames.
                // Ignore our border ids to avoid transaction feedback loops.
                if !controller.missionControlState.active,
                   MacWindow.allWindowsMap[windowId] != nil,
                   [UInt32(723), 806, 807, 808].contains(event) {
                    controller.refresh()
                }
            }
        }) {
            print("WinMuxX: Mission Control WindowServer notifications unavailable")
        }
        missionControlChanged()
    }

    func missionControlChanged() {
        guard !isUnitTest else { return }
        // Include ordered-out windows so exit notifications are subscribed too.
        let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let ids = Set(all.compactMap { entry -> UInt32? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  NSRunningApplication(processIdentifier: pid.int32Value)?.bundleIdentifier == "com.apple.WindowManager",
                  let id = entry[kCGWindowNumber as String] as? NSNumber else { return nil }
            return id.uint32Value
        })
        if ids != missionControlWindowIds {
            missionControlWindowIds = ids
            let watched = Array(ids.union(MacWindow.allWindowsMap.keys))
            watched.withUnsafeBufferPointer { winmux_watch_windows($0.baseAddress, Int32($0.count)) }
        }
        let onscreen = all.filter { ($0[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true }
        let active = isMissionControlVisible(onscreen, screenSizes: NSScreen.screens.map { $0.frame.size },
            bundleIdentifierForPID: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier })
        guard let transition = missionControlState.update(active: active) else { return }
        if transition { WindowMotion.shared.finishAll(); clear() } else { refresh() }
    }
    private func refreshMovingBorder(_ windowId: UInt32) {
        guard config.windowBorders.enabled, !missionControlState.active,
              let window = MacWindow.allWindowsMap[windowId], !window.isHiddenInCorner,
              let border = borders[windowId] else { return }
        var frame = CGRect.zero
        guard winmux_window_frame(windowId, &frame) else { return }
        border.update(frame: frame, active: focus.windowOrNil?.windowId == windowId, settings: config.windowBorders)
    }
    func refresh() {
        guard !isUnitTest else { return }
        guard !missionControlState.active else { clear(); return }
        let settings = config.windowBorders
        guard TrayMenuModel.shared.isEnabled, settings.enabled, settings.width > 0, !shouldSuppressChromeForNativeFullscreenContent else { clear(); return }
        let native = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard !isMissionControlVisible(native, screenSizes: NSScreen.screens.map { $0.frame.size }, bundleIdentifierForPID: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }) else { clear(); return }
        var frames: [UInt32: CGRect] = [:]
        for entry in native { guard let n = entry[kCGWindowNumber as String] as? NSNumber, let b = entry[kCGWindowBounds as String] as? NSDictionary, let f = CGRect(dictionaryRepresentation: b) else { continue }; frames[n.uint32Value] = f }
        var visible = Set<UInt32>()
        for workspace in Workspace.all where workspace.isVisible { for window in workspace.allLeafWindowsRecursive {
            if let bundle = window.app.rawAppBundleId, settings.excludeApps.contains(bundle) { continue }
            guard window.participatesInWorkspaceFocus, !window.isHiddenInCorner, !window.isFullscreen, let nf = frames[window.windowId], nf.width > 0, nf.height > 0 else { continue }
            visible.insert(window.windowId)
            // CGWindowList reports the transformed overview thumbnail during
            // Mission Control exit. SkyLight bounds retain the actual frame.
            var nativeFrame = CGRect.zero
            let hasNativeFrame = winmux_window_frame(window.windowId, &nativeFrame)
            let f = resolvedWindowBorderFrame(snapshot: nf, nativeFrame: hasNativeFrame ? nativeFrame : nil)
            let border = borders[window.windowId] ?? WindowBorder(target: window.windowId); borders[window.windowId] = border
            border.update(frame: f, active: focus.windowOrNil?.windowId == window.windowId, settings: settings)
        }}
        for id in Array(borders.keys) where !visible.contains(id) { borders.removeValue(forKey: id)?.destroy() }
    }
    func clear() { borders.values.forEach { $0.destroy() }; borders.removeAll() }
    func remove(windowId: UInt32) { borders.removeValue(forKey: windowId)?.destroy() }
}

struct MissionControlBorderState {
    private(set) var active = false
    /// Returns the new state only when borders need hiding/restoring.
    mutating func update(active: Bool) -> Bool? {
        guard self.active != active else { return nil }
        self.active = active
        return active
    }
}

func resolvedWindowBorderFrame(snapshot: CGRect, nativeFrame: CGRect?) -> CGRect {
    nativeFrame ?? snapshot
}

@MainActor private final class WindowBorder {
    let target: UInt32; private var nativeID: UInt32 = 0; private var frame: CGRect?; private var appearance: Appearance?; private var scale: CGFloat = 0
    var windowId: UInt32 { nativeID }
    init(target: UInt32) { self.target = target }
    deinit { if nativeID != 0 { winmux_border_destroy(nativeID) } }
    func update(frame: CGRect, active: Bool, settings: WindowBordersConfig) {
        let cocoaFrame = CGRect(x: frame.minX, y: mainMonitor.height - frame.maxY, width: frame.width, height: frame.height)
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        let s = NSScreen.screens.first(where: { $0.frame.contains(center) })?.backingScaleFactor ?? 2
        if nativeID == 0 || scale != s { if nativeID != 0 { winmux_border_destroy(nativeID) }; guard winmux_border_create(Float(s), &nativeID) else { nativeID = 0; print("WinMuxX: unable to create SkyLight border for window \(target)"); return }; scale = s; self.frame = nil; appearance = nil }
        let a = Appearance(settings: settings, active: active)
        if appearance != a || self.frame?.size != frame.size { winmux_border_update(nativeID, target, frame, Float(systemWindowCornerRadius()), a.rgba, Float(settings.width), settings.order == .above); appearance = a }
        else { winmux_border_move(nativeID, target, frame, Float(settings.width), settings.order == .above) }
        self.frame = frame
    }
    func destroy() { if nativeID != 0 { winmux_border_hide(nativeID); winmux_border_destroy(nativeID); nativeID = 0 } }
}

private struct Appearance: Equatable {
    let settings: WindowBordersConfig
    let rgba: UInt32
    init(settings: WindowBordersConfig, active: Bool) { self.settings = settings; let h = active ? settings.activeColor : settings.inactiveColor; let v = UInt32(h.dropFirst(), radix: 16) ?? 0; let rgb = h.count == 9 ? v >> 8 : v; let alpha = h.count == 9 ? v & 255 : 255; rgba = (rgb << 8) | alpha }
}

func isMissionControlVisible(_ windows: [[String: Any]], screenSizes: [CGSize], bundleIdentifierForPID: (pid_t) -> String?) -> Bool {
    windows.contains { w in guard let p = (w[kCGWindowOwnerPID as String] as? NSNumber).map({ pid_t($0.int32Value) }), bundleIdentifierForPID(p) == "com.apple.WindowManager", let l = (w[kCGWindowLayer as String] as? NSNumber)?.intValue, l == 19, let b = w[kCGWindowBounds as String] as? NSDictionary, let f = CGRect(dictionaryRepresentation: b), f.width > 0, f.height > 0 else { return false }; return screenSizes.contains { abs($0.width - f.width) < 2 && abs($0.height - f.height) < 2 } }
}
