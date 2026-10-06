import AppKit
import Common
import QuartzCore
import PrivateApi

/// Finite, retargetable layout motion. No clock runs when all windows have landed.
struct WindowMotionFrame {
    var start: CGRect
    var target: CGRect

    func frame(progress: Double) -> CGRect {
        let t = min(1, max(0, progress))
        let eased = t * t * (3 - 2 * t)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * eased }
        return CGRect(x: mix(start.minX, target.minX), y: mix(start.minY, target.minY),
                      width: mix(start.width, target.width), height: mix(start.height, target.height))
    }
}

@MainActor
final class WindowMotion: NSObject {
    static let shared = WindowMotion()
    private struct Playback {
        weak var window: MacWindow?
        let motion: WindowMotionFrame
        let duration: Double
        var elapsed = 0.0
    }
    private var jobs: [UInt32: Playback] = [:]
    private var frames: [UInt32: CGRect] = [:]
    private var targets: [UInt32: CGRect] = [:]
    private var displayPolicy = WindowMotionDisplayPolicy()
    private var newWindows = Set<UInt32>()
    private var displayLink: WindowMotionClock?
    private var lastTick: Double?
    private var stallTimeout: Task<Void, Never>?

    func noteNewWindow(_ id: UInt32) { newWindows.insert(id) }

    func isAnimating(_ id: UInt32) -> Bool { jobs[id] != nil }

    func screensChanged() {
        displayPolicy.screensChanged(windowIds: Set(MacWindow.allWindowsMap.keys))
        for id in Array(jobs.keys) { cancel(id) }
        for app in MacApp.allAppsMap.values { app.cancelPendingFrameWrites() }
        for window in MacWindow.allWindows {
            window.lastAppliedLayoutPhysicalRect = nil
            window.suspendMinimumObservationForMotion()
        }
    }

    func screensSettled() { displayPolicy.screensSettled() }

    func forget(_ id: UInt32) {
        cancel(id)
        displayPolicy.forget(id)
    }

    func cancel(_ id: UInt32) {
        newWindows.remove(id)
        jobs.removeValue(forKey: id)
        frames.removeValue(forKey: id)
        targets.removeValue(forKey: id)
        if jobs.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
            lastTick = nil
            stallTimeout?.cancel()
            stallTimeout = nil
        }
    }

    func finishAll() {
        for (id, target) in targets {
            MacWindow.allWindowsMap[id]?.setAxFrame(target.origin, target.size)
        }
    }

    func apply(_ window: Window, target: CGRect) {
        let target = windowMotionNativeTarget(target)
        let snap = displayPolicy.shouldSnap(window.windowId)
        guard let window = window as? MacWindow else {
            window.setAxFrame(target.origin, target.size)
            return
        }
        let id = window.windowId
        let isNewWindow = newWindows.remove(id) != nil
        // AX move/resize events reassert the same tile while we are travelling.
        // They must not restart the clock indefinitely.
        if !snap, targets[id] == target, config.animations.enabled, config.animations.durationMs > 0,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }
        let cachedStart = window.lastKnownActualRect.map {
            CGRect(x: $0.topLeftX, y: $0.topLeftY, width: $0.width, height: $0.height)
        }
        // AX geometry events invalidate the cache after every layout. Read native
        // bounds once at departure, rather than skipping motion when that cache is cold.
        var nativeStart = CGRect.zero
        let hasNativeStart = !isUnitTest && winmux_window_frame(id, &nativeStart)
        let departure = frames[id] ?? (hasNativeStart ? nativeStart : cachedStart)
        let monitorRect = window.nodeMonitor?.visibleRectPaddedByOuterGaps
        let destination = monitorRect.map {
            CGRect(x: $0.topLeftX, y: $0.topLeftY, width: $0.width, height: $0.height)
        }
        let start = departure.map {
            windowMotionOrigin(nativeFrame: $0, destination: destination, isNewWindow: isNewWindow)
        }
        cancel(id)
        guard !snap, config.animations.enabled, config.animations.durationMs > 0,
              TrayMenuModel.shared.isEnabled, !WindowBorderController.shared.isMissionControlActive,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !isUnitTest, let start, start != target, !window.isHiddenInCorner else {
            window.setAxFrame(target.origin, target.size)
            return
        }
        WindowRecoveryController.shared.recordBeforeMutation(window, originalRect: window.lastKnownActualRect)
        window.suspendMinimumObservationForMotion()
        let motion = WindowMotionFrame(start: start, target: target)
        let duration = Double(config.animations.durationMs) / 1000
        targets[id] = target
        jobs[id] = Playback(window: window, motion: motion, duration: duration)
        if displayLink == nil {
            let index = (window.nodeMonitor?.monitorAppKitNsScreenScreensId ?? 1) - 1
            let screens = NSScreen.screens
            let screen = screens.indices.contains(index) ? screens[index] : screens.first
            if let screen {
                displayLink = WindowMotionClock(screen: screen) { [weak self] timestamp, duration in
                    self?.tick(timestamp: timestamp, duration: duration)
                }
            }
        }
        // One finite safety deadline: a disconnected display must not strand tiles.
        stallTimeout?.cancel()
        stallTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(duration + 1)) } catch { return }
            self?.finishAll()
        }
        if displayLink == nil { finishAll() }
    }

    private func tick(timestamp: Double, duration: Double) {
        let dt = windowMotionFrameDelta(previous: lastTick, current: timestamp, fallback: duration)
        lastTick = timestamp
        for (id, var playback) in jobs {
            guard let window = playback.window, MacWindow.allWindowsMap[id] === window else { cancel(id); continue }
            guard TrayMenuModel.shared.isEnabled, !window.isHiddenInCorner,
                  currentlyManipulatedWithMouseWindowId != id,
                  !WindowRecoveryController.shared.suppressAutomaticFrameWrites,
                  !WindowBorderController.shared.isMissionControlActive else {
                window.lastAppliedLayoutPhysicalRect = nil
                cancel(id)
                continue
            }
            playback.elapsed += dt
            let progress = playback.elapsed / playback.duration
            if progress >= 1 || !config.animations.enabled || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let target = playback.motion.target
                window.setAxFrame(target.origin, target.size)
                continue
            }
            jobs[id] = playback
            let raw = playback.motion.frame(progress: progress)
            let frame = CGRect(x: raw.minX.rounded(), y: raw.minY.rounded(),
                               width: raw.width.rounded(), height: raw.height.rounded())
            if frames[id] == frame { continue }
            frames[id] = frame
            // Intermediate frames bypass minimum-size learning; only the final tile is observed.
            window.macApp.setAnimatedAxFrame(id, frame)
        }
    }
}

/// AX clients commonly quantize geometry to whole points. Quantize the edges
/// once, before comparing targets, so fractional tiles cannot restart motion.
func windowMotionNativeTarget(_ frame: CGRect) -> CGRect {
    let x = frame.minX.rounded()
    let y = frame.minY.rounded()
    return CGRect(x: x, y: y, width: frame.maxX.rounded() - x, height: frame.maxY.rounded() - y)
}

/// A single refresh clock for all moving windows; invalidated immediately at rest.
@MainActor
private final class WindowMotionClock: NSObject {
    private var source: AnyObject?
    private var fallback: Timer?
    private let frame: (Double, Double) -> Void

    init(screen: NSScreen, frame: @escaping (Double, Double) -> Void) {
        self.frame = frame
        super.init()
        if #available(macOS 14, *) {
            let link = screen.displayLink(target: self, selector: #selector(displayFrame))
            source = link
            link.add(to: .main, forMode: .common)
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.frame(CACurrentMediaTime(), 1.0 / 60) }
            }
            fallback = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @available(macOS 14, *)
    @objc private func displayFrame(_ link: CADisplayLink) { frame(link.timestamp, link.duration) }

    func invalidate() {
        if #available(macOS 14, *) { (source as? CADisplayLink)?.invalidate() }
        source = nil
        fallback?.invalidate()
        fallback = nil
    }
}

/// Advance on refresh ticks without jumping through a long main-thread stall.
func windowMotionFrameDelta(previous: Double?, current: Double, fallback: Double) -> Double {
    min(1.0 / 30, max(0, previous.map { current - $0 } ?? fallback))
}

/// Only a freshly created window is repositioned before gliding. Existing windows
/// (including an interrupted glide) always depart from their current geometry.
func windowMotionOrigin(nativeFrame: CGRect, destination: CGRect?, isNewWindow: Bool) -> CGRect {
    guard isNewWindow, let destination, destination.width > 0, destination.height > 0,
          !destination.contains(nativeFrame) else { return nativeFrame }
    let size = CGSize(width: min(nativeFrame.width, destination.width), height: min(nativeFrame.height, destination.height))
    let centerIsInside = destination.contains(CGPoint(x: nativeFrame.midX, y: nativeFrame.midY))
    let x = centerIsInside ? nativeFrame.minX : destination.midX - size.width / 2
    let y = centerIsInside ? nativeFrame.minY : destination.midY - size.height / 2
    return CGRect(x: min(max(x, destination.minX), destination.maxX - size.width),
                  y: min(max(y, destination.minY), destination.maxY - size.height),
                  width: size.width, height: size.height)
}

/// Hidden windows retain their pending snap until their first settled layout.
struct WindowMotionDisplayPolicy {
    private var pending = Set<UInt32>()
    private var changing = false

    mutating func screensChanged(windowIds: Set<UInt32>) {
        pending.formUnion(windowIds)
        changing = true
    }

    mutating func screensSettled() { changing = false }

    mutating func forget(_ id: UInt32) { pending.remove(id) }

    mutating func shouldSnap(_ id: UInt32) -> Bool {
        if changing { return true }
        return pending.remove(id) != nil
    }
}
