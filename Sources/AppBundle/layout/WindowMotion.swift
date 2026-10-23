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
        let displayID: CGDirectDisplayID
        let deadline: Double
        var elapsed = 0.0
    }
    private var jobs: [UInt32: Playback] = [:]
    private var frames: [UInt32: CGRect] = [:]
    private var targets: [UInt32: CGRect] = [:]
    private var landed = WindowMotionRestingFrames()
    private var displayPolicy = WindowMotionDisplayPolicy()
    private struct DisplayClockState {
        let clock: WindowMotionClock
        var lastTick: Double?
        var deadlineTask: Task<Void, Never>?
        var deadlineGeneration: UInt64 = 0
    }
    private var displayClocks: [CGDirectDisplayID: DisplayClockState] = [:]

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
        let oldDisplay = jobs[id]?.displayID
        jobs.removeValue(forKey: id)
        frames.removeValue(forKey: id)
        targets.removeValue(forKey: id)
        if let oldDisplay { retireClockIfIdle(oldDisplay) }
    }

    func cancelAll() {
        for id in Array(jobs.keys) { cancel(id) }
        for app in MacApp.allAppsMap.values { app.cancelPendingFrameWrites() }
    }

    func finishAll() {
        for (id, playback) in jobs {
            if let window = playback.window, MacWindow.allWindowsMap[id] === window {
                let target = playback.motion.target
                window.setAxFrame(target.origin, target.size)
            }
        }
        jobs.removeAll(); frames.removeAll(); targets.removeAll()
        for (_, clock) in displayClocks { clock.deadlineTask?.cancel(); clock.clock.invalidate() }
        displayClocks.removeAll()
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
        let displayID = window.nodeMonitor?.displayUUID.flatMap { uuid in NSScreen.screens.first(where: { $0.displayUUID == uuid })?.displayId }
            ?? NSScreen.screens.first(where: { $0.frame.intersects(target) })?.displayId
            ?? NSScreen.screens.first?.displayId ?? CGDirectDisplayID(0)
        targets[id] = target
        let deadline = ProcessInfo.processInfo.systemUptime + duration + 1
        jobs[id] = Playback(window: window, motion: motion, duration: duration,
                            displayID: displayID, deadline: deadline)
        startClockIfNeeded(displayID, target: target)
        scheduleDeadline(for: displayID)
    }

    private func startClockIfNeeded(_ displayID: CGDirectDisplayID, target: CGRect) {
        guard displayClocks[displayID] == nil else { return }
        let screen = NSScreen.screens.first(where: { $0.displayId == displayID })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(target) })
            ?? NSScreen.main
        guard let screen else { finishAll(); return }
        let clock = WindowMotionClock(screen: screen) { [weak self] timestamp, duration in
            self?.tick(displayID: displayID, timestamp: timestamp, duration: duration)
        }
        displayClocks[displayID] = DisplayClockState(clock: clock)
    }

    private func tick(displayID: CGDirectDisplayID, timestamp: Double, duration: Double) {
        guard var clock = displayClocks[displayID] else { return }
        let dt = windowMotionFrameDelta(previous: clock.lastTick, current: timestamp, fallback: duration)
        clock.lastTick = timestamp
        displayClocks[displayID] = clock
        for (id, var playback) in Array(jobs) where playback.displayID == displayID {
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
                jobs.removeValue(forKey: id)
                frames[id] = nil
                targets[id] = nil
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
        retireClockIfIdle(displayID)
    }

    private func scheduleDeadline(for displayID: CGDirectDisplayID) {
        guard var clock = displayClocks[displayID] else { return }
        clock.deadlineTask?.cancel()
        clock.deadlineGeneration &+= 1
        let generation = clock.deadlineGeneration
        let earliest = jobs.values.filter { $0.displayID == displayID }.map(\.deadline).min()
        guard let earliest else {
            displayClocks[displayID] = clock
            retireClockIfIdle(displayID)
            return
        }
        clock.deadlineTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, earliest - ProcessInfo.processInfo.systemUptime))) }
            catch { return }
            guard let self, self.displayClocks[displayID]?.deadlineGeneration == generation else { return }
            self.finishExpired(displayID)
        }
        displayClocks[displayID] = clock
    }

    private func finishExpired(_ displayID: CGDirectDisplayID) {
        let now = ProcessInfo.processInfo.systemUptime
        for (id, playback) in Array(jobs) where playback.displayID == displayID && playback.deadline <= now {
            guard let window = playback.window, MacWindow.allWindowsMap[id] === window else { cancel(id); continue }
            window.setAxFrame(playback.motion.target.origin, playback.motion.target.size)
            jobs[id] = nil
            frames[id] = nil
            targets[id] = nil
        }
        scheduleDeadline(for: displayID)
        retireClockIfIdle(displayID)
    }

    private func retireClockIfIdle(_ displayID: CGDirectDisplayID) {
        guard !jobs.values.contains(where: { $0.displayID == displayID }),
              let clock = displayClocks.removeValue(forKey: displayID) else { return }
        clock.deadlineTask?.cancel()
        clock.clock.invalidate()
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
