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
        let session = UUID()
        weak var window: MacWindow?
        let motion: WindowMotionFrame
        let duration: Double
        var elapsed = 0.0
    }
    private var jobs: [UInt32: Playback] = [:]
    private var frames: [UInt32: CGRect] = [:]
    private var targets: [UInt32: CGRect] = [:]
    private var landed = WindowMotionRestingFrames()
    private var displayPolicy = WindowMotionDisplayPolicy()
    private var displayLink: WindowMotionClock?
    private var lastTick: Double?
    private var stallTimeout: Task<Void, Never>?

    func snapOnNextLayout(_ id: UInt32) {
        cancel(id)
        displayPolicy.snapOnNextLayout(id)
    }

    func isAnimating(_ id: UInt32) -> Bool { jobs[id] != nil }

    func screensChanged() {
        landed.removeAll()
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
        landed.forget(id)
        displayPolicy.forget(id)
    }

    func noteLanded(_ id: UInt32, asked: CGRect, got: CGRect) {
        landed.record(id, asked: windowMotionNativeTarget(asked), got: got)
    }

    func cancel(_ id: UInt32) {
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

    func cancelAll() {
        for id in Array(jobs.keys) { cancel(id) }
        for app in MacApp.allAppsMap.values { app.cancelPendingFrameWrites() }
    }

    func finishAll() {
        for (id, target) in targets {
            MacWindow.allWindowsMap[id]?.setAxFrame(target.origin, target.size)
        }
    }

    func apply(_ window: Window, target: CGRect) async throws {
        let target = windowMotionNativeTarget(target)
        let snap = displayPolicy.shouldSnap(window.windowId)
        guard let window = window as? MacWindow else {
            window.setAxFrame(target.origin, target.size)
            return
        }
        let id = window.windowId
        if window.isHiddenInCorner {
            cancel(id)
            _ = try await window.restoreFromCorner(to: target)
            return
        }
        if snap {
            cancel(id)
            try await window.setAxFrameBlocking(target.origin, target.size)
            return
        }
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
        // Travel directly from the actual window position to the tile. An ongoing
        // glide keeps its latest frame when retargeted, without a synthetic waypoint.
        let start = windowMotionDeparture(inFlight: frames[id],
                                          nativeFrame: hasNativeStart ? nativeStart : nil,
                                          cachedFrame: cachedStart)
        if !snap, let start, landed.matches(id, asked: target, actual: start) {
            cancel(id)
            return
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
            window.macApp.setAnimatedAxFrame(id, frame, session: playback.session)
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

/// Preserve the current animation frame, otherwise prefer authoritative native
/// geometry. A window on another display still departs from that display.
func windowMotionDeparture(inFlight: CGRect?, nativeFrame: CGRect?, cachedFrame: CGRect?) -> CGRect? {
    inFlight ?? nativeFrame ?? cachedFrame
}

/// Hidden windows retain their pending snap until their first settled layout.
struct WindowMotionDisplayPolicy {
    private var pending = Set<UInt32>()
    private var changing = false

    mutating func snapOnNextLayout(_ id: UInt32) { pending.insert(id) }

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

/// Quantized or refused sizes can settle away from the requested frame.
struct WindowMotionRestingFrames {
    private var values: [UInt32: (asked: CGRect, got: CGRect)] = [:]
    mutating func record(_ id: UInt32, asked: CGRect, got: CGRect) { values[id] = (asked, got) }
    mutating func forget(_ id: UInt32) { values[id] = nil }
    mutating func removeAll() { values.removeAll() }
    func matches(_ id: UInt32, asked: CGRect, actual: CGRect) -> Bool {
        guard let value = values[id], value.asked == asked else { return false }
        return abs(value.got.minX - actual.minX) <= 1 && abs(value.got.minY - actual.minY) <= 1 &&
            abs(value.got.width - actual.width) <= 1 && abs(value.got.height - actual.height) <= 1
    }
}
