import AppKit
import Common
import PrivateApi
import QuartzCore
import NativeSpaces

@MainActor
final class WindowBorderController {
    static let shared = WindowBorderController()
    private var borders: [UInt32: WindowBorder] = [:]
    private var documentWindowCache: [UInt32: Bool] = [:]
    private var borderWindowIds = Set<UInt32>()
    private var watchedWindowIds = Set<UInt32>()
    private let nativeRefresh = NativeWindowRefreshScheduler()
    private var nativeBorderRefreshRequested = false
    private var movingBorders = WindowBorderMotionTracking()
    private var missionControlState = MissionControlBorderState()
    var isMissionControlActive: Bool { missionControlState.active }
    private(set) var missionControlWindowIds = Set<UInt32>()
    var backendDiagnosticSummary: String {
        let native = borders.values.filter(\.usesNativeBackend).count
        let fallback = borders.count - native
        return "native=\(native) AppKitFallback=\(fallback) activeBorders=\(borders.count)"
    }

    func setEnabled(_ enabled: Bool) {
        nativeRefresh.cancel()
        nativeBorderRefreshRequested = false
        if enabled {
            // Native events were ignored while disabled; re-observe before
            // motion/swipes consult the cached Mission Control state.
            missionControlChanged(refreshBorders: true)
        } else {
            missionControlState = MissionControlBorderState()
            clear()
        }
    }

    func startMissionControlMonitoring() {
        guard !isUnitTest else { return }
        if !winmux_watch_mission_control({ event, windowId in
            MainActor.assumeIsolated {
                let controller = WindowBorderController.shared
                // Our own reshape/order notifications cannot change Mission Control.
                // Scanning every border transaction creates a geometry feedback storm.
                guard TrayMenuModel.shared.isEnabled else { return }
                if windowId != 0, controller.borderWindowIds.contains(windowId) { return }
                if [UInt32(723), 806, 807, 808].contains(event) {
                    WorkspaceTransitionDiagnostics.recordNativeEvent(event, windowId: windowId)
                    if runtime.workspaceBackend.kind == .virtual {
                        HiddenWorkspaceWindowRecovery.shared.nativeGeometryChanged(windowId)
                    }
                }
                if !controller.missionControlState.active,
                   [UInt32(723), 806, 807, 808].contains(event),
                   controller.borders[windowId] != nil {
                    controller.windowGeometryChanged(windowId)
                    return
                }
                if MacWindow.allWindowsMap[windowId] != nil,
                   [UInt32(723), 806, 807, 808].contains(event) {
                    controller.nativeBorderRefreshRequested = true
                }
                controller.nativeRefresh.request { [weak controller] in
                    guard let controller, TrayMenuModel.shared.isEnabled else { return }
                    let refreshBorders = controller.nativeBorderRefreshRequested
                    controller.nativeBorderRefreshRequested = false
                    controller.missionControlChanged(refreshBorders: refreshBorders)
                }
            }
        }) {
            print("WinMuxX: Mission Control WindowServer notifications unavailable")
        }
        missionControlChanged()
    }

    func missionControlChanged(refreshBorders: Bool = false) {
        guard !isUnitTest else { return }
        // Include ordered-out windows so exit notifications are subscribed too.
        let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        var bundles: [pid_t: String] = [:]
        func bundleIdentifier(_ pid: pid_t) -> String? {
            if let bundle = bundles[pid] { return bundle.isEmpty ? nil : bundle }
            let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            bundles[pid] = bundle ?? ""
            return bundle
        }
        let ids = Set(all.compactMap { entry -> UInt32? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  bundleIdentifier(pid.int32Value) == "com.apple.WindowManager",
                  let id = entry[kCGWindowNumber as String] as? NSNumber else { return nil }
            return id.uint32Value
        })
        missionControlWindowIds = ids
        synchronizeNativeWindowSubscriptions()
        let onscreen = all.filter { ($0[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true }
        let active = isMissionControlVisible(onscreen, screenSizes: NSScreen.screens.map { $0.frame.size },
            bundleIdentifierForPID: bundleIdentifier)
        let transition = missionControlState.update(active: active)
        if transition == true {
            WorkspaceOverviewController.shared.dismiss(restoreFocus: false)
            WindowMotion.shared.finishAll()
            clear()
        } else if !active, transition != nil || refreshBorders {
            refresh(nativeSnapshot: onscreen)
        }
    }
    private func synchronizeNativeWindowSubscriptions() {
        let watched = missionControlWindowIds.union(MacWindow.allWindowsMap.keys)
        guard watched != watchedWindowIds else { return }
        watchedWindowIds = watched
        let ids = Array(watched)
        ids.withUnsafeBufferPointer { winmux_watch_windows($0.baseAddress, Int32($0.count)) }
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
        guard isBorderEligibleDocument(windowId) else { remove(windowId: windowId); return }
        var frame = CGRect.zero
        guard winmux_window_frame(windowId, &frame) else { return }
        guard let target = windowBorderTarget(for: window, nativeFrame: frame) else {
            remove(windowId: windowId)
            return
        }
        border.update(frame: target.frame, active: focus.windowOrNil?.windowId == windowId,
            settings: config.windowBorders, corners: target.corners)
    }
    func refresh(nativeSnapshot: [[String: Any]]? = nil) {
        guard !isUnitTest else { return }
        synchronizeNativeWindowSubscriptions()
        guard !missionControlState.active else { clear(); return }
        let settings = config.windowBorders
        guard TrayMenuModel.shared.isEnabled, settings.enabled, settings.width > 0, !shouldSuppressChromeForNativeFullscreenContent else { clear(); return }
        let native = nativeSnapshot ?? (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
        guard !isMissionControlVisible(native, screenSizes: NSScreen.screens.map { $0.frame.size }, bundleIdentifierForPID: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }) else { clear(); return }
        var frames: [UInt32: CGRect] = [:]
        for entry in native {
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
            frames[number.uint32Value] = frame
        }
        var visible = Set<UInt32>()
        for workspace in Workspace.all where workspace.isVisible {
            for window in workspace.allLeafWindowsRecursive {
                if WorkspacePresentationController.shared.suppressesChrome(for: window) { continue }
                if let bundle = window.app.rawAppBundleId, settings.excludeApps.contains(bundle) { continue }
                guard window.participatesInWorkspaceFocus, !window.isHiddenInCorner, !window.isFullscreen,
                      let snapshot = frames[window.windowId], snapshot.width > 0, snapshot.height > 0 else { continue }
                guard isBorderEligibleDocument(window.windowId) else { continue }
                // Overview thumbnails can have transformed bounds; native bounds
                // retain the application's actual frame throughout the transition.
                var nativeFrame = CGRect.zero
                let hasNativeFrame = winmux_window_frame(window.windowId, &nativeFrame)
                let frame = resolvedWindowBorderFrame(snapshot: snapshot, nativeFrame: hasNativeFrame ? nativeFrame : nil)
                guard let target = windowBorderTarget(for: window, nativeFrame: frame) else { continue }
                visible.insert(window.windowId)
                let border = borders[window.windowId] ?? WindowBorder(target: window.windowId)
                borders[window.windowId] = border
                border.update(frame: target.frame, active: focus.windowOrNil?.windowId == window.windowId,
                    settings: settings, corners: target.corners)
            }
        }
        for id in Array(borders.keys) where !visible.contains(id) { borders.removeValue(forKey: id)?.destroy() }
        borderWindowIds = Set(borders.values.flatMap(\.windowIds))
    }
    func clear() {
        movingBorders = WindowBorderMotionTracking()
        DisplayRefreshDriver.shared.remove(owner: self)
        borders.values.forEach { $0.destroy() }
        borders.removeAll()
        borderWindowIds.removeAll()
        documentWindowCache.removeAll()
    }
    func remove(windowId: UInt32) {
        documentWindowCache.removeValue(forKey: windowId)
        if let border = borders.removeValue(forKey: windowId) {
            borderWindowIds.subtract(border.windowIds)
            border.destroy()
        }
    }

    private func isBorderEligibleDocument(_ windowId: UInt32) -> Bool {
        if let cached = documentWindowCache[windowId] { return cached }
        // If the private SkyLight query is unavailable, keep the previous AX-based
        // behavior rather than suppressing borders on unsupported macOS versions.
        let nativeResult = winmux_window_document_kind(windowId)
        let eligible = nativeResult != 0
        documentWindowCache[windowId] = eligible
        return eligible
    }
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
    private var geometry: WindowBorderGeometry?
    private var corners: WindowBorderCornerRadii?
    private var appearance: Appearance?
    private var scale: CGFloat = 0
    private var fallbackPanels: [WindowBorderFallbackPanel] = []
    private let createNativeBorder: (Float, inout OpaquePointer?) -> Bool
    private let updateNativeBorder: (OpaquePointer?, UInt32, CGRect, Float, UInt32, Float, Bool, CGPath?) -> Bool
    private let destroyNativeBorder: (OpaquePointer?) -> Void

    var windowIds: [UInt32] {
        if let nativeID { return (0..<4).map { winmux_border_window_id(nativeID, Int32($0)) }.filter { $0 != 0 } }
        return fallbackPanels.map { UInt32(max($0.windowNumber, 0)) }.filter { $0 != 0 }
    }

    var windowId: UInt32 { windowIds.first ?? 0 }
    var usesNativeBackend: Bool { nativeID != nil }

    init(
        target: UInt32,
        createNativeBorder: @escaping (Float, inout OpaquePointer?) -> Bool = { scale, id in winmux_border_create(scale, &id) },
        updateNativeBorder: @escaping (OpaquePointer?, UInt32, CGRect, Float, UInt32, Float, Bool, CGPath?) -> Bool = winmux_border_update,
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

    func update(frame: CGRect, active: Bool, settings: WindowBordersConfig, corners: WindowBorderCornerRadii? = nil) {
        let nextCorners = corners ?? .init(top: systemWindowCornerRadius(), bottom: systemWindowCornerRadius())
        var cocoaFrame = CGRect(x: frame.minX, y: mainMonitor.height - frame.maxY,
                                width: frame.width, height: frame.height)
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        let nextScale = NSScreen.screens.first(where: { $0.frame.contains(center) })?.backingScaleFactor ?? 2
        let frame = pixelAlignedWindowBorderFrame(frame, width: CGFloat(settings.width), scale: nextScale)
        cocoaFrame = CGRect(x: frame.minX, y: mainMonitor.height - frame.maxY,
            width: frame.width, height: frame.height)
        if !fallbackPanels.isEmpty {
            updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale, corners: nextCorners)
            return
        }
        if nativeID == nil || scale != nextScale {
            if let nativeID { destroyNativeBorder(nativeID) }
            nativeID = nil
            guard createNativeBorder(Float(nextScale), &nativeID) else {
                if let nativeID { destroyNativeBorder(nativeID) }
                nativeID = nil
                updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale, corners: nextCorners)
                return
            }
            scale = nextScale
            self.frame = nil
            appearance = nil
        }
        let nextAppearance = Appearance(settings: settings, active: active)
        if appearance == nextAppearance, self.frame == frame, self.corners == nextCorners { return }
        if appearance != nextAppearance || self.frame?.size != frame.size || self.corners != nextCorners {
            let radius = nextCorners.maximum
            let outerSize = frame.insetBy(dx: -CGFloat(settings.width), dy: -CGFloat(settings.width)).size
            let path = borderGeometry(size: outerSize, corners: nextCorners, width: CGFloat(settings.width), scale: nextScale).path
            guard updateNativeBorder(nativeID, target, frame, Float(radius),
                                       nextAppearance.rgba, Float(settings.width), settings.order == .above, path) else {
                if let nativeID { destroyNativeBorder(nativeID) }
                nativeID = nil
                updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale, corners: nextCorners)
                return
            }
            appearance = nextAppearance
        } else {
            if !winmux_border_move(nativeID, target, frame, Float(settings.width), settings.order == .above) {
                if let nativeID { destroyNativeBorder(nativeID) }
                nativeID = nil
                updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale, corners: nextCorners)
                return
            }
        }
        self.frame = frame
        self.corners = nextCorners
    }

    private func borderGeometry(size: CGSize, corners: WindowBorderCornerRadii, width: CGFloat, scale: CGFloat) -> WindowBorderGeometry {
        let bottomRadius = corners.bottom == corners.top ? nil : corners.bottom
        let key = WindowBorderGeometry.Key(size: size, radius: corners.top, width: width, scale: scale, bottomRadius: bottomRadius)
        if let geometry, geometry.key == key { return geometry }
        let updated = WindowBorderGeometry(size: size, radius: corners.top, width: width, scale: scale, bottomRadius: bottomRadius)
        geometry = updated
        return updated
    }

    private func updateFallback(frame: CGRect, active: Bool, settings: WindowBordersConfig, scale: CGFloat, corners: WindowBorderCornerRadii) {
        if fallbackPanels.isEmpty { fallbackPanels = (0..<4).map { _ in WindowBorderFallbackPanel() } }
        let alignedFrame = pixelAlignedWindowBorderFrame(frame, width: CGFloat(settings.width), scale: scale)
        let outer = alignedFrame.insetBy(dx: -CGFloat(settings.width), dy: -CGFloat(settings.width))
        let radius = corners.maximum
        let path = borderGeometry(size: outer.size, corners: corners, width: CGFloat(settings.width), scale: scale).path
        for (index, panel) in fallbackPanels.enumerated() {
            let piece = winmux_border_piece(outer.size, Float(radius), Float(settings.width), Float(scale), Int32(index))
            panel.update(outer: outer, piece: piece, radius: radius, path: path, windowId: target, active: active, settings: settings)
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
    NativeSpaceTransitionGuard.isMissionControlVisible(windows, screenSizes: screenSizes,
        bundleIdentifierForPID: bundleIdentifierForPID)
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

    func update(outer: CGRect, piece: CGRect, radius: CGFloat, path: CGPath, windowId: UInt32, active: Bool, settings: WindowBordersConfig) {
        guard !piece.isEmpty else { orderOut(nil); return }
        let frame = CGRect(x: outer.minX + piece.minX, y: outer.maxY - piece.maxY,
            width: piece.width, height: piece.height)
        if self.frame != frame { setFrame(frame, display: false) }
        let geometryChanged = borderView.outerSize != outer.size || borderView.piece != piece || borderView.radius != radius || borderView.path !== path
        if geometryChanged || borderView.settings != settings || borderView.active != active {
            borderView.settings = settings
            borderView.active = active
            borderView.outerSize = outer.size
            borderView.piece = piece
            borderView.radius = radius
            borderView.path = path
            borderView.needsDisplay = true
        }
        order(settings.order == .above ? .above : .below, relativeTo: Int(windowId))
    }
}

@MainActor
private final class WindowBorderFallbackView: NSView {
    override var isFlipped: Bool { true }
    var settings = WindowBordersConfig()
    var active = false
    var outerSize = CGSize.zero
    var piece = CGRect.zero
    var radius: CGFloat = 0
    var path: CGPath?

    override func draw(_ dirtyRect: NSRect) {
        let hex = active ? settings.activeColor : settings.inactiveColor
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        let rgb = hex.count == 9 ? value >> 8 : value
        let alpha = hex.count == 9 ? CGFloat(value & 255) / 255 : 1
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rgbValue = UInt32(rgb)
        let rgba = (rgbValue << 8) | UInt32(round(alpha * 255))
        if let path { winmux_border_draw_path(context, piece, path, rgba) }
    }
}
