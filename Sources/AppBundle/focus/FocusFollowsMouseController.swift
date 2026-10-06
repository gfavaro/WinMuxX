import AppKit

/// State machine for focus-follows-mouse. It is intentionally independent from NSEvent and
/// workspace objects so dwell and cancellation behavior can be tested without Accessibility.
@MainActor
final class FocusFollowsMouseController {
    static let shared = FocusFollowsMouseController()
    struct Candidate: Equatable {
        let windowId: UInt32
        let point: CGPoint
        let startedAt: TimeInterval
    }

    private(set) var candidate: Candidate?
    private(set) var lastFocusedWindowId: UInt32?

    init() {}

    func notePointer(windowId: UInt32?, point: CGPoint, timestamp: TimeInterval) -> UInt32? {
        guard let windowId else {
            candidate = nil
            return nil
        }
        if candidate?.windowId != windowId || candidate?.point != point {
            candidate = Candidate(windowId: windowId, point: point, startedAt: timestamp)
            return nil
        }
        return candidate.flatMap { timestamp - $0.startedAt >= 0 ? $0.windowId : nil }
    }

    func isReady(dwell: TimeInterval, timestamp: TimeInterval) -> UInt32? {
        guard dwell >= 0, let candidate,
              timestamp - candidate.startedAt >= dwell else { return nil }
        return candidate.windowId
    }

    func markFocused(_ windowId: UInt32) {
        lastFocusedWindowId = windowId
        candidate = nil
    }

    func cancel() {
        candidate = nil
    }
}
