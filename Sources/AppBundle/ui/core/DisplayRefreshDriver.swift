import AppKit
import QuartzCore

@MainActor
final class DisplayRefreshDriver {
    static let shared = DisplayRefreshDriver()

    private struct Subscription {
        weak var owner: AnyObject?
        let callback: (CFTimeInterval) -> Void
    }

    private var subscriptions: [ObjectIdentifier: Subscription] = [:]
    /// Calls back on the main run loop, once per frame of the fastest display.
    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?

    private init() {
        // The link follows one display: when displays come or go, bind to the fastest again.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DisplayRefreshDriver.shared.rebindDisplayLink() }
        }
    }

    private func rebindDisplayLink() {
        guard displayLink != nil || fallbackTimer != nil else { return }
        displayLink?.invalidate()
        displayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        startIfNeeded()
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
        guard let screen = NSScreen.screens.max(by: { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond }) else { return false }
        let link = screen.displayLink(target: DisplayRefreshLinkTarget { [weak self] in self?.fire(timestamp: $0) },
                                      selector: #selector(DisplayRefreshLinkTarget.frame))
        link.add(to: .main, forMode: .common)
        displayLink = link
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
        displayLink?.invalidate()
        displayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
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

    private func fire(timestamp: CFTimeInterval) {
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

/// The display link's target: it holds the link's callback, as the link retains its target.
@MainActor
private final class DisplayRefreshLinkTarget: NSObject {
    private let callback: (CFTimeInterval) -> Void

    init(_ callback: @escaping (CFTimeInterval) -> Void) { self.callback = callback }

    @objc func frame(_ link: CADisplayLink) { callback(link.timestamp) }
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
