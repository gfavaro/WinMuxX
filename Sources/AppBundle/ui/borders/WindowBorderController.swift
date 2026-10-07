import AppKit
import Common
import PrivateApi
import QuartzCore

@MainActor
final class WindowBorderController {
    static let shared = WindowBorderController()
    private var borders: [UInt32: WindowBorder] = [:]
    private var movingBorders = WindowBorderMotionTracking()
    private var missionControlState = MissionControlBorderState()
    var isMissionControlActive: Bool { missionControlState.active }
    private(set) var missionControlWindowIds = Set<UInt32>()

    func startMissionControlMonitoring() {
        guard !isUnitTest else { return }
        if !winmux_watch_mission_control({ event, windowId in
            MainActor.assumeIsolated {
                let controller = WindowBorderController.shared
                // Our own reshape/order notifications cannot change Mission Control.
                // Scanning every border transaction creates a geometry feedback storm.
                if controller.borders.values.contains(where: { $0.windowIds.contains(windowId) && windowId != 0 }) { return }
                if !controller.missionControlState.active,
                   [UInt32(723), 806, 807, 808].contains(event),
                   controller.borders[windowId] != nil {
                    controller.windowGeometryChanged(windowId)
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
    func windowGeometryChanged(_ windowId: UInt32) {
        guard !isUnitTest, borders[windowId] != nil, !missionControlState.active else { return }
        refreshMovingBorder(windowId)
        // Poll only the moving window between notifications, which can arrive well
        // after the WindowServer has already moved the content.
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return }
        movingBorders.note(windowId, at: CACurrentMediaTime())
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] timestamp in
            guard let self else { return }
            let ids = self.movingBorders.active(at: timestamp, mouseDown: NSEvent.pressedMouseButtons & 1 != 0)
            for id in ids { self.refreshMovingBorder(id) }
            if ids.isEmpty { DisplayRefreshDriver.shared.remove(owner: self) }
        }
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
    func clear() {
        movingBorders = WindowBorderMotionTracking()
        DisplayRefreshDriver.shared.remove(owner: self)
        borders.values.forEach { $0.destroy() }
        borders.removeAll()
    }
    func remove(windowId: UInt32) { borders.removeValue(forKey: windowId)?.destroy() }
}

/// A short lease keeps tracking alive between drag notifications, then stops at rest.
struct WindowBorderMotionTracking {
    private var lastEvents: [UInt32: CFTimeInterval] = [:]

    mutating func note(_ windowId: UInt32, at timestamp: CFTimeInterval) {
        lastEvents[windowId] = timestamp
    }

    mutating func active(at timestamp: CFTimeInterval, mouseDown: Bool) -> [UInt32] {
        let pending = Array(lastEvents.keys)
        guard mouseDown else {
            lastEvents.removeAll()
            return pending // One final position update on release.
        }
        lastEvents = lastEvents.filter { timestamp - $0.value < 0.15 }
        return Array(lastEvents.keys)
    }
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

@MainActor
final class WindowBorder {
    let target: UInt32
    private var nativeID: OpaquePointer?
    private var frame: CGRect?
    private var appearance: Appearance?
    private var scale: CGFloat = 0
    private var fallbackPanels: [WindowBorderFallbackPanel] = []
    private let createNativeBorder: (Float, inout OpaquePointer?) -> Bool
    private let updateNativeBorder: (OpaquePointer?, UInt32, CGRect, Float, UInt32, Float, Bool) -> Bool
    private let destroyNativeBorder: (OpaquePointer?) -> Void

    var windowIds: [UInt32] {
        if let nativeID { return (0..<4).map { winmux_border_window_id(nativeID, Int32($0)) }.filter { $0 != 0 } }
        return fallbackPanels.map { UInt32(max($0.windowNumber, 0)) }.filter { $0 != 0 }
    }

    var windowId: UInt32 { windowIds.first ?? 0 }

    init(
        target: UInt32,
        createNativeBorder: @escaping (Float, inout OpaquePointer?) -> Bool = { scale, id in winmux_border_create(scale, &id) },
        updateNativeBorder: @escaping (OpaquePointer?, UInt32, CGRect, Float, UInt32, Float, Bool) -> Bool = winmux_border_update,
        destroyNativeBorder: @escaping (OpaquePointer?) -> Void = winmux_border_destroy
    ) {
        self.target = target
        self.createNativeBorder = createNativeBorder
        self.updateNativeBorder = updateNativeBorder
        self.destroyNativeBorder = destroyNativeBorder
    }

    isolated deinit {
        if let nativeID { destroyNativeBorder(nativeID) }
        fallbackPanels.forEach { $0.close() }
    }

    func update(frame: CGRect, active: Bool, settings: WindowBordersConfig) {
        let cocoaFrame = CGRect(x: frame.minX, y: mainMonitor.height - frame.maxY,
                                width: frame.width, height: frame.height)
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        let nextScale = NSScreen.screens.first(where: { $0.frame.contains(center) })?.backingScaleFactor ?? 2
        if !fallbackPanels.isEmpty {
            updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale)
            return
        }
        if nativeID == nil || scale != nextScale {
            if let nativeID { destroyNativeBorder(nativeID) }
            nativeID = nil
            guard createNativeBorder(Float(nextScale), &nativeID) else {
                if let nativeID { destroyNativeBorder(nativeID) }
                nativeID = nil
                updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale)
                return
            }
            scale = nextScale
            self.frame = nil
            appearance = nil
        }
        let nextAppearance = Appearance(settings: settings, active: active)
        if appearance == nextAppearance, self.frame == frame { return }
        if appearance != nextAppearance || self.frame?.size != frame.size {
            guard updateNativeBorder(nativeID, target, frame, Float(systemWindowCornerRadius()),
                                       nextAppearance.rgba, Float(settings.width), settings.order == .above) else {
                if let nativeID { destroyNativeBorder(nativeID) }
                nativeID = nil
                updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale)
                return
            }
            appearance = nextAppearance
        } else {
            if !winmux_border_move(nativeID, target, frame, Float(settings.width), settings.order == .above) {
                if let nativeID { destroyNativeBorder(nativeID) }
                nativeID = nil
                updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale)
                return
            }
        }
        self.frame = frame
    }

    private func updateFallback(frame: CGRect, active: Bool, settings: WindowBordersConfig, scale: CGFloat) {
        if fallbackPanels.isEmpty { fallbackPanels = (0..<4).map { _ in WindowBorderFallbackPanel() } }
        let outer = frame.insetBy(dx: -CGFloat(settings.width), dy: -CGFloat(settings.width))
        let radius = systemWindowCornerRadius()
        for (index, panel) in fallbackPanels.enumerated() {
            let piece = winmux_border_piece(outer.size, Float(radius), Float(settings.width), Float(scale), Int32(index))
            panel.update(outer: outer, piece: piece, radius: radius, windowId: target, active: active, settings: settings)
        }
    }

    func destroy() {
        if let nativeID {
            winmux_border_hide(nativeID)
            destroyNativeBorder(nativeID)
            self.nativeID = nil
        }
        fallbackPanels.forEach { $0.close() }
        fallbackPanels.removeAll()
    }
}

private struct Appearance: Equatable {
    let settings: WindowBordersConfig
    let rgba: UInt32
    init(settings: WindowBordersConfig, active: Bool) { self.settings = settings; let h = active ? settings.activeColor : settings.inactiveColor; let v = UInt32(h.dropFirst(), radix: 16) ?? 0; let rgb = h.count == 9 ? v >> 8 : v; let alpha = h.count == 9 ? v & 255 : 255; rgba = (rgb << 8) | alpha }
}

func isMissionControlVisible(_ windows: [[String: Any]], screenSizes: [CGSize], bundleIdentifierForPID: (pid_t) -> String?) -> Bool {
    windows.contains { w in guard let p = (w[kCGWindowOwnerPID as String] as? NSNumber).map({ pid_t($0.int32Value) }), bundleIdentifierForPID(p) == "com.apple.WindowManager", let l = (w[kCGWindowLayer as String] as? NSNumber)?.intValue, l == 19, let b = w[kCGWindowBounds as String] as? NSDictionary, let f = CGRect(dictionaryRepresentation: b), f.width > 0, f.height > 0 else { return false }; return screenSizes.contains { abs($0.width - f.width) < 2 && abs($0.height - f.height) < 2 } }
}

// Public AppKit fallback when the private WindowServer renderer is unavailable.
@MainActor
private final class WindowBorderFallbackPanel: NSPanelHud {
    private let borderView = WindowBorderFallbackView()


    override init() {
        super.init()
        level = .normal
        hasShadow = false
        ignoresMouseEvents = true
        isFloatingPanel = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        // Transient panels are hidden by Exposé/Mission Control. Stationary panels
        // deliberately remain visible there, even before our next refresh can detect it.
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        contentView = borderView
        borderView.autoresizingMask = [.width, .height]
    }

    // Edge panels must retain their exact coordinates across menu-bar boundaries.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(outer: CGRect, piece: CGRect, radius: CGFloat, windowId: UInt32, active: Bool, settings: WindowBordersConfig) {
        guard !piece.isEmpty else { orderOut(nil); return }
        let frame = piece.offsetBy(dx: outer.minX, dy: outer.minY)
        if self.frame != frame { setFrame(frame, display: false) }
        let geometryChanged = borderView.outerSize != outer.size || borderView.piece != piece || borderView.radius != radius
        if geometryChanged || borderView.settings != settings || borderView.active != active {
            borderView.settings = settings
            borderView.active = active
            borderView.outerSize = outer.size
            borderView.piece = piece
            borderView.radius = radius
            borderView.needsDisplay = true
        }
        order(settings.order == .above ? .above : .below, relativeTo: Int(windowId))
    }
}

@MainActor
private final class WindowBorderFallbackView: NSView {
    var settings = WindowBordersConfig()
    var active = false
    var outerSize = CGSize.zero
    var piece = CGRect.zero
    var radius: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        let hex = active ? settings.activeColor : settings.inactiveColor
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        let rgb = hex.count == 9 ? value >> 8 : value
        let alpha = hex.count == 9 ? CGFloat(value & 255) / 255 : 1
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rgbValue = UInt32(rgb)
        let rgba = (rgbValue << 8) | UInt32(round(alpha * 255))
        winmux_border_draw(context, outerSize, piece, Float(radius), rgba, Float(settings.width))
    }
}
