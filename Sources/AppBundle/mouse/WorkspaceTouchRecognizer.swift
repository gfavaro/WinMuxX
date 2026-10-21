import Foundation

struct WorkspaceTouchFrame: Equatable, Sendable {
    let device: UInt64
    let fingers: Int
    let x: Double
    let y: Double
    let timestamp: Double
    let contacts: UInt64
}

/// A gesture previews one adjacent workspace; only release can commit it.
struct WorkspaceTouchRecognizer {
    private static let fullTravel = 0.24
    struct Request: Equatable {
        let displayPoint: CGPoint
        let isNext: Bool
        let progress: Double
        let slidesLeft: Bool
    }
    enum Event: Equatable {
        case began(Request)
        case changed(Double)
        case ended(Bool)
        case cancelled
    }
    private var owner: UInt64?
    private var anchor: WorkspaceTouchFrame?
    private var displayPoint: CGPoint?
    private var direction: Double?
    private var progress = 0.0
    private var finished = false
    private var previous: WorkspaceTouchFrame?
    private var velocity = 0.0

    private func shouldCommit(at timestamp: Double) -> Bool {
        let fresh = previous.map { timestamp >= $0.timestamp && timestamp - $0.timestamp < 0.08 } ?? false
        return progress >= 0.5 || (progress >= 0.16 && fresh && velocity >= 2.5)
    }

    mutating func cancel() {
        anchor = nil
        direction = nil
        finished = true
    }

    private mutating func abort() -> Event? {
        let wasPreviewing = direction != nil
        cancel()
        return wasPreviewing ? .cancelled : nil
    }

    mutating func receive(_ frame: WorkspaceTouchFrame, displayPoint point: CGPoint?, reversed: Bool) -> Event? {
        if frame.fingers < 0 { return abort() }
        if let owner, frame.device != owner { return nil }
        if frame.fingers == 0 {
            let event: Event? = !finished && direction != nil ? .ended(shouldCommit(at: frame.timestamp)) : nil
            self = WorkspaceTouchRecognizer()
            return event
        }
        guard !finished else { return nil }
        if frame.fingers == 1 || frame.fingers == 2 {
            // Fingers rarely lift simultaneously. Freeze the last three-finger sample
            // at the first lift, then wait for all contacts to leave before rearming.
            if direction != nil {
                let commit = shouldCommit(at: frame.timestamp)
                cancel()
                return .ended(commit)
            }
            if anchor != nil { return abort() }
            return nil
        }
        guard frame.fingers == 3 else { return abort() }
        guard frame.x.isFinite, frame.y.isFinite, frame.timestamp.isFinite,
              (0...1).contains(frame.x), (0...1).contains(frame.y) else { return abort() }
        guard let anchor else {
            owner = frame.device
            self.anchor = frame
            previous = frame
            displayPoint = point
            return nil
        }
        guard anchor.contacts == frame.contacts, frame.timestamp >= anchor.timestamp,
              frame.timestamp - anchor.timestamp <= 10 else { return abort() }
        if let previous, frame.timestamp > previous.timestamp {
            let dt = frame.timestamp - previous.timestamp
            let sign = direction ?? (frame.x < anchor.x ? -1.0 : 1.0)
            velocity = dt <= 0.1 ? (frame.x - previous.x) * sign / Self.fullTravel / dt : 0
        }
        previous = frame
        let dx = frame.x - anchor.x
        let dy = frame.y - anchor.y
        if direction == nil {
            if abs(dy) >= 0.04 && abs(dy) > abs(dx) { return abort() }
            guard abs(dx) >= 0.02, abs(dx) >= abs(dy) * 1.5, let displayPoint else { return nil }
            direction = dx < 0 ? -1 : 1
            progress = min(1, abs(dx) / Self.fullTravel)
            return .began(Request(displayPoint: displayPoint, isNext: (dx < 0) != reversed, progress: progress, slidesLeft: dx < 0))
        }
        progress = min(1, max(0, dx * direction! / Self.fullTravel))
        return .changed(progress)
    }
}

