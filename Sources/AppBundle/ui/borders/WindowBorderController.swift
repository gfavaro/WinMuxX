import AppKit
import Common
import PrivateApi
import QuartzCore

@MainActor
final class WindowBorderController {
    static let shared = WindowBorderController()
    private var borders: [UInt32: WindowBorder] = [:]
    /// Hidden borders of parked windows. Every switch parks the outgoing workspace's windows,
    /// and the incoming ones reuse these instead of creating new WindowServer windows.
    private var spareBorders: [WindowBorder] = []
    private let spareBorderLimit = 4
    /// Set once a border fell back to AppKit: the native renderer then fails for every border,
    /// and each attempt created and drew WindowServer windows before failing.
    private var nativeBordersUnavailable = false
    private var documentWindowCache: [UInt32: Bool] = [:]
    private var borderWindowIds = Set<UInt32>()
    private var watchedWindowIds = Set<UInt32>()
    private let nativeRefresh = NativeWindowRefreshScheduler()
    private var nativeBorderRefreshRequested = false
    private var nativeRefreshTrigger: String?
    /// False while every coalesced event only moved or reordered a managed window.
    private var nativeRefreshNeedsScan = false
    private var movingBorders = WindowBorderMotionTracking()
    private var missionControlState = MissionControlBorderState()
    var isMissionControlActive: Bool { missionControlState.active }
    private(set) var missionControlWindowIds = Set<UInt32>()
    /// Windows named by events since the last check whose owner is not known yet.
    private var unseenWindowIds = Set<UInt32>()
    /// Windows already found not to belong to Mission Control.
    private var otherWindowIds = Set<UInt32>()
    private var nativeRefreshNeedsFullScan = false
    var backendDiagnosticSummary: String {
        let native = borders.values.filter(\.usesNativeBackend).count
        let fallback = borders.count - native
        return "native=\(native) AppKitFallback=\(fallback) activeBorders=\(borders.count)"
    }

    func setEnabled(_ enabled: Bool) {
        nativeRefresh.cancel()
        nativeBorderRefreshRequested = false
        nativeRefreshTrigger = nil
        if enabled {
            // Native events were ignored while disabled; re-observe before
            // motion/swipes consult the cached Mission Control state.
            missionControlChanged(refreshBorders: true)
        } else {
            missionControlState = MissionControlBorderState()
            clear()
            InactiveWindowDimmer.shared.hide()
            WindowHoverBar.shared.hide()
        }
    }

    private var colorObservers: [Any] = []

    /// Redraws `accent` borders when the accent color or the light/dark appearance changes; the
    /// refresh compares resolved colors, so fixed colors are left alone.
    func startColorMonitoring() {
        guard !isUnitTest, colorObservers.isEmpty else { return }
        colorObservers.append(NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WindowBorderController.shared.refresh() }
        })
        colorObservers.append(NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in WindowBorderController.shared.refresh() }
        })
    }

    func startMissionControlMonitoring() {
        guard !isUnitTest else { return }
        if !winmux_watch_mission_control({ event, windowId in
            MainActor.assumeIsolated {
                let controller = WindowBorderController.shared
                // Our own reshape/order notifications cannot change Mission Control.
                // Scanning every border transaction creates a geometry feedback storm, and the
                // dimmer, sidebar and swipe preview change on every refresh and slide.
                guard TrayMenuModel.shared.isEnabled else { return }
                if windowId != 0, controller.borderWindowIds.contains(windowId) || NSApp.window(withWindowNumber: Int(windowId)) != nil { return }
                if [UInt32(723), 806, 807, 808].contains(event) {
                    WorkspaceTransitionDiagnostics.recordNativeEvent(event, windowId: windowId)
                    HiddenWorkspaceWindowRecovery.shared.nativeGeometryChanged(windowId)
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
                } else {
                    controller.nativeRefreshNeedsScan = true
                    if windowId == 0 {
                        controller.nativeRefreshNeedsFullScan = true
                    } else if MacWindow.allWindowsMap[windowId] == nil, !controller.missionControlWindowIds.contains(windowId),
                              !controller.otherWindowIds.contains(windowId) {
                        controller.unseenWindowIds.insert(windowId)
                    }
                }
                if controller.nativeRefreshTrigger == nil {
                    controller.nativeRefreshTrigger = windowId == 0 ? "space"
                        : controller.missionControlWindowIds.contains(windowId) ? "Mission Control window"
                        : MacWindow.allWindowsMap[windowId] != nil ? "managed window" : "other window"
                }
                controller.nativeRefresh.request { [weak controller] in
                    guard let controller, TrayMenuModel.shared.isEnabled else { return }
                    let refreshBorders = controller.nativeBorderRefreshRequested
                    let trigger = controller.nativeRefreshTrigger ?? "other window"
                    let scan = controller.nativeRefreshNeedsScan
                    let fullScan = controller.nativeRefreshNeedsFullScan
                    controller.nativeBorderRefreshRequested = false
                    controller.nativeRefreshTrigger = nil
                    controller.nativeRefreshNeedsScan = false
                    controller.nativeRefreshNeedsFullScan = false
                    let start = CACurrentMediaTime()
                    if scan || controller.missionControlState.active {
                        controller.missionControlChanged(refreshBorders: refreshBorders, fullScan: fullScan)
                        WorkspaceMotionDiagnostics.record("Window scan after \(trigger) event", milliseconds: (CACurrentMediaTime() - start) * 1000)
                    } else {
                        // Moving a managed window cannot open Mission Control: only its border needs
                        // the new frames. Every switch moves the parked and revealed windows, and
                        // listing every window waited for WindowServer through each slide.
                        controller.refresh(onScreenFrames: onScreenWindowFrames(controller.borderCandidateWindowIds))
                        WorkspaceMotionDiagnostics.record("Border refresh after managed window event", milliseconds: (CACurrentMediaTime() - start) * 1000)
                    }
                }
            }
        }) {
            print("WinMuxX: Mission Control WindowServer notifications unavailable")
        }
        missionControlChanged()
    }

    /// `fullScan` lists every window on the system, ordered out or not, to find Mission Control's.
    /// Otherwise only its known windows and the windows events named since are described: the
    /// system has over a thousand windows, and listing them took most of each check.
    func missionControlChanged(refreshBorders: Bool = false, fullScan: Bool = true) {
        guard !isUnitTest else { return }
        let all: [[String: Any]]
        if fullScan {
            // Include ordered-out windows so exit notifications are subscribed too.
            all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
            otherWindowIds.removeAll()
        } else {
            all = windowDescriptions(Array(missionControlWindowIds.union(unseenWindowIds).union(borderCandidateWindowIds)))
        }
        unseenWindowIds.removeAll()
        // Runs after every WindowServer window event; only Mission Control's owner matters.
        var bundles: [pid_t: String?] = [:]
        func bundleIdentifier(_ pid: pid_t) -> String? {
            if let bundle = bundles[pid] { return bundle }
            let bundle = windowManagerBundleIdentifier(pid)
            bundles[pid] = bundle
            return bundle
        }
        var ids = Set<UInt32>()
        for entry in all {
            guard let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = entry[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            if bundleIdentifier(pid.int32Value) == "com.apple.WindowManager" {
                ids.insert(id)
            } else if !fullScan, MacWindow.allWindowsMap[id] == nil {
                if otherWindowIds.count > 4096 { otherWindowIds.removeAll() }
                otherWindowIds.insert(id)
            }
        }
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
    private var borderCandidateWindowIds: [UInt32] {
        Workspace.all.filter(\.isVisible).flatMap { $0.allLeafWindowsRecursive.map(\.windowId) }
    }

    /// `onScreenFrames` holds the on-screen frames of the visible workspaces' windows, read without
    /// listing every window; Mission Control is then known not to be showing.
    func refresh(nativeSnapshot: [[String: Any]]? = nil, onScreenFrames: [UInt32: CGRect]? = nil) {
        guard !isUnitTest else { return }
        synchronizeNativeWindowSubscriptions()
        var chromeAllowed = false
        defer { InactiveWindowDimmer.shared.refresh(chromeAllowed: chromeAllowed) }
        chromeAllowed = !missionControlState.active
        guard !missionControlState.active else { clear(); return }
        let settings = config.windowBorders
        guard TrayMenuModel.shared.isEnabled, settings.enabled, settings.width > 0 else { clear(); return }
        var frames = onScreenFrames ?? [:]
        if onScreenFrames == nil {
            let native = nativeSnapshot ?? (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            guard !isMissionControlVisible(native, screenSizes: NSScreen.screens.map { $0.frame.size },
                bundleIdentifierForPID: windowManagerBundleIdentifier) else {
                chromeAllowed = false
                clear()
                return
            }
            for entry in native {
                guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                      let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
                frames[number.uint32Value] = frame
            }
        }
        var visible = Set<UInt32>()
        // A border whose window left the screen moves to the next window that needs one: creating
        // a border makes new WindowServer windows, and a workspace switch replaces every border.
        let onVisibleWorkspaces = Set(borderCandidateWindowIds)
        var reusable = borders.keys.filter { !onVisibleWorkspaces.contains($0) }
        for workspace in Workspace.all where workspace.isVisible && !shouldSuppressChromeForFullscreenContent(on: workspace.workspaceMonitor) {
            for window in workspace.allLeafWindowsRecursive {
                if let bundle = window.app.rawAppBundleId, settings.excludeApps.contains(bundle) { continue }
                guard window.participatesInWorkspaceFocus, !window.isHiddenInCorner, !window.isFullscreen, !window.isInactiveWindowTab,
                      let snapshot = frames[window.windowId], snapshot.width > 0, snapshot.height > 0 else { continue }
                guard isBorderEligibleDocument(window.windowId) else { continue }
                // Overview thumbnails can have transformed bounds; native bounds
                // retain the application's actual frame throughout the transition.
                var nativeFrame = CGRect.zero
                let hasNativeFrame = winmux_window_frame(window.windowId, &nativeFrame)
                let frame = resolvedWindowBorderFrame(snapshot: snapshot, nativeFrame: hasNativeFrame ? nativeFrame : nil)
                guard let target = windowBorderTarget(for: window, nativeFrame: frame) else { continue }
                visible.insert(window.windowId)
                let border = borders[window.windowId]
                    ?? (reusable.popLast().flatMap { borders.removeValue(forKey: $0) } ?? spareBorders.popLast())?.retarget(window.windowId)
                    ?? (nativeBordersUnavailable ? WindowBorder(target: window.windowId, createNativeBorder: { _, _ in false }) : WindowBorder(target: window.windowId))
                borders[window.windowId] = border
                border.update(frame: target.frame, active: focus.windowOrNil?.windowId == window.windowId,
                    settings: settings, corners: target.corners)
                if !border.usesNativeBackend { nativeBordersUnavailable = true }
            }
        }
        for id in Array(borders.keys) where !visible.contains(id) { borders.removeValue(forKey: id)?.destroy() }
        borderWindowIds = Set((borders.values + spareBorders).flatMap(\.windowIds))
    }
    func clear() {
        movingBorders = WindowBorderMotionTracking()
        DisplayRefreshDriver.shared.remove(owner: self)
        (borders.values + spareBorders).forEach { $0.destroy() }
        borders.removeAll()
        spareBorders.removeAll()
        borderWindowIds.removeAll()
        documentWindowCache.removeAll()
    }
    func remove(windowId: UInt32) {
        documentWindowCache.removeValue(forKey: windowId)
        if let border = borders.removeValue(forKey: windowId) {
            if spareBorders.count < spareBorderLimit {
                // Its windows stay ours, so their notifications are still ignored.
                border.hide()
                spareBorders.append(border)
            } else {
                borderWindowIds.subtract(border.windowIds)
                border.destroy()
            }
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
    private(set) var target: UInt32
    /// The window the native pieces were last ordered against.
    private var placedTarget: UInt32?
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
        if let nativeID { return (0..<Int(WINMUX_BORDER_PIECES)).map { winmux_border_window_id(nativeID, Int32($0)) }.filter { $0 != 0 } }
        return fallbackPanels.map { UInt32(max($0.windowNumber, 0)) }.filter { $0 != 0 }
    }

    var windowId: UInt32 { windowIds.first ?? 0 }

    func retarget(_ target: UInt32) -> WindowBorder {
        self.target = target
        return self
    }
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
        let display = monitors.first { $0.rect.contains(CGPoint(x: frame.midX, y: frame.midY)) }
            .map { CGRect(x: $0.rect.minX, y: $0.rect.minY, width: $0.rect.width, height: $0.rect.height) }
        let onDisplay = windowBorderFrame(frame, width: CGFloat(settings.width), within: display)
        let nextCorners = corners ?? .init(top: systemWindowCornerRadius(), bottom: systemWindowCornerRadius())
        var cocoaFrame = CGRect(x: onDisplay.minX, y: mainMonitor.height - onDisplay.maxY,
                                width: onDisplay.width, height: onDisplay.height)
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        let nextScale = NSScreen.screens.first(where: { $0.frame.contains(center) })?.backingScaleFactor ?? 2
        let frame = pixelAlignedWindowBorderFrame(onDisplay, width: CGFloat(settings.width), scale: nextScale)
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
        if appearance == nextAppearance, self.frame == frame, self.corners == nextCorners, placedTarget == target { return }
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
        placedTarget = target
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
        if fallbackPanels.isEmpty { fallbackPanels = (0..<Int(WINMUX_BORDER_PIECES)).map { _ in WindowBorderFallbackPanel() } }
        let alignedFrame = pixelAlignedWindowBorderFrame(frame, width: CGFloat(settings.width), scale: scale)
        let outer = alignedFrame.insetBy(dx: -CGFloat(settings.width), dy: -CGFloat(settings.width))
        let radius = corners.maximum
        let path = borderGeometry(size: outer.size, corners: corners, width: CGFloat(settings.width), scale: scale).path
        for (index, panel) in fallbackPanels.enumerated() {
            let piece = winmux_border_piece(outer.size, Float(radius), Float(settings.width), Float(scale), Int32(index))
            panel.update(outer: outer, piece: piece, radius: radius, path: path, windowId: target, active: active, settings: settings)
        }
    }

    /// Orders the border out but keeps its windows for the next target.
    func hide() {
        if let nativeID { winmux_border_hide(nativeID) }
        fallbackPanels.forEach { $0.orderOut(nil) }
        placedTarget = nil
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

/// The resolved color is part of the value: an accent change redraws on the next refresh.
@MainActor
private struct Appearance: Equatable {
    let settings: WindowBordersConfig
    let rgba: UInt32
    init(settings: WindowBordersConfig, active: Bool) {
        self.settings = settings
        rgba = windowBorderRGBA(active ? settings.activeColor : settings.inactiveColor)
    }
}

/// Current-host Mission Control overlay signature. This is a heuristic, not a
/// documented Mission Control API, and must be validated on each supported OS.
func isMissionControlVisible(_ windows: [[String: Any]], screenSizes: [CGSize], bundleIdentifierForPID: (pid_t) -> String?) -> Bool {
    windows.contains { window in
        // Layer first: the bundle lookup creates an NSRunningApplication per window.
        guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 19,
              let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              bundleIdentifierForPID(pid) == "com.apple.WindowManager",
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 0, frame.height > 0 else { return false }
        return screenSizes.contains { abs($0.width - frame.width) < 2 && abs($0.height - frame.height) < 2 }
    }
}

private let windowManagerPath = "/System/Library/CoreServices/WindowManager.app/Contents/MacOS/WindowManager"

/// `com.apple.WindowManager` for the process that draws Mission Control, otherwise nil.
/// The only bundle these checks ask about, answered from the process's executable path:
/// a system call rather than a synchronous LaunchServices request per process.
func windowManagerBundleIdentifier(_ pid: pid_t) -> String? {
    executablePath(ofProcess: pid) == windowManagerPath ? "com.apple.WindowManager" : nil
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
        // The path is rebuilt for every update: compared by identity it always differed, and
        // every piece redrew on each focus or geometry refresh even when nothing changed.
        let geometryChanged = borderView.outerSize != outer.size || borderView.piece != piece || borderView.radius != radius || borderView.path != path
        let rgba = windowBorderRGBA(active ? settings.activeColor : settings.inactiveColor)
        if geometryChanged || borderView.rgba != rgba {
            borderView.rgba = rgba
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
    var rgba: UInt32 = 0
    var outerSize = CGSize.zero
    var piece = CGRect.zero
    var radius: CGFloat = 0
    var path: CGPath?

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if let path { winmux_border_draw_path(context, piece, path, rgba) }
    }
}
