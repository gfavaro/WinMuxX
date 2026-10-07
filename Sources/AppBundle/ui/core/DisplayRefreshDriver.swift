import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore
import os

private let displayRefreshHostClockFrequency = CVGetHostClockFrequency()

private func displayRefreshDriverCallback(
    _: CVDisplayLink,
    _ now: UnsafePointer<CVTimeStamp>,
    _: UnsafePointer<CVTimeStamp>,
    _: CVOptionFlags,
    _: UnsafeMutablePointer<CVOptionFlags>,
    _ userInfo: UnsafeMutableRawPointer?,
) -> CVReturn {
    guard let userInfo else { return kCVReturnSuccess }
    let driver = Unmanaged<DisplayRefreshDriver>.fromOpaque(userInfo).takeUnretainedValue()
    let timestamp = displayRefreshHostClockFrequency > 0
        ? Double(now.pointee.hostTime) / displayRefreshHostClockFrequency
        : CACurrentMediaTime()
    driver.enqueueFrame(timestamp: timestamp)
    return kCVReturnSuccess
}

/// Backpressure between the display-link thread and the main actor. A busy main
/// actor needs the most recent frame, rather than a queue of obsolete frames.
final class DisplayRefreshFrameMailbox: Sendable {
    private struct State {
        var timestamp: CFTimeInterval?
        var generation: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func enqueue(timestamp: CFTimeInterval) -> UInt64? {
        state.withLock { state in
            let needsDelivery = state.timestamp == nil
            state.timestamp = timestamp
            return needsDelivery ? state.generation : nil
        }
    }

    func take(generation: UInt64) -> CFTimeInterval? {
        state.withLock { state in
            guard generation == state.generation else { return nil }
            defer { state.timestamp = nil }
            return state.timestamp
        }
    }

    func reset() {
        state.withLock { state in
            state.generation &+= 1
            state.timestamp = nil
        }
    }
}

@MainActor
final class DisplayRefreshDriver {
    static let shared = DisplayRefreshDriver()

    private struct Subscription {
        weak var owner: AnyObject?
        let callback: (CFTimeInterval) -> Void
    }

    private var subscriptions: [ObjectIdentifier: Subscription] = [:]
    private var displayLink: CVDisplayLink?
    private var fallbackTimer: Timer?
    nonisolated private let frameMailbox = DisplayRefreshFrameMailbox()

    private init() {}

    nonisolated fileprivate func enqueueFrame(timestamp: CFTimeInterval) {
        guard let generation = frameMailbox.enqueue(timestamp: timestamp) else { return }
        Task { @MainActor in
            guard let timestamp = frameMailbox.take(generation: generation) else { return }
            fire(timestamp: timestamp)
        }
    }

    func add(owner: AnyObject, callback: @escaping (CFTimeInterval) -> Void) {
        subscriptions[ObjectIdentifier(owner)] = Subscription(owner: owner, callback: callback)
        startIfNeeded()
    }

    func remove(owner: AnyObject) {
        subscriptions.removeValue(forKey: ObjectIdentifier(owner))
        stopIfIdle()
    }

    private func startIfNeeded() {
        guard !subscriptions.isEmpty, displayLink == nil, fallbackTimer == nil else { return }
        if startDisplayLink() {
            return
        }
        startFallbackTimer()
    }

    private func startDisplayLink() -> Bool {
        var rawLink: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&rawLink) == kCVReturnSuccess,
              let rawLink
        else {
            return false
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard CVDisplayLinkSetOutputCallback(rawLink, displayRefreshDriverCallback, userInfo) == kCVReturnSuccess,
              CVDisplayLinkStart(rawLink) == kCVReturnSuccess
        else {
            return false
        }
        displayLink = rawLink
        return true
    }

    private func startFallbackTimer() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fire(timestamp: CACurrentMediaTime())
            }
        }
        fallbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopIfIdle() {
        pruneReleasedOwners()
        guard subscriptions.isEmpty else { return }
        if let displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        frameMailbox.reset()
    }

    private func pruneReleasedOwners() {
        var releasedOwners: [ObjectIdentifier]?
        for (id, subscription) in subscriptions where subscription.owner == nil {
            if releasedOwners == nil {
                releasedOwners = []
            }
            releasedOwners?.append(id)
        }
        guard let releasedOwners else { return }
        for id in releasedOwners {
            subscriptions.removeValue(forKey: id)
        }
    }

    fileprivate func fire(timestamp: CFTimeInterval) {
        pruneReleasedOwners()
        guard !subscriptions.isEmpty else {
            stopIfIdle()
            return
        }
        for subscription in subscriptions.values {
            subscription.callback(timestamp)
        }
    }

}

func displayRefreshEaseInOut(_ progress: CGFloat) -> CGFloat {
    let clamped = min(max(progress, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
}

func displayRefreshInterpolate(_ start: CGFloat, _ end: CGFloat, progress: CGFloat) -> CGFloat {
    start + (end - start) * progress
}

func displayRefreshInterpolate(_ start: CGRect, _ end: CGRect, progress: CGFloat) -> CGRect {
    CGRect(
        x: displayRefreshInterpolate(start.minX, end.minX, progress: progress),
        y: displayRefreshInterpolate(start.minY, end.minY, progress: progress),
        width: displayRefreshInterpolate(start.width, end.width, progress: progress),
        height: displayRefreshInterpolate(start.height, end.height, progress: progress),
    )
}
