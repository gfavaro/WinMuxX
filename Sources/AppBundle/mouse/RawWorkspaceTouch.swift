import AppKit
import Common
import PrivateApi
import os

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

/// Driver threads copy scalar summaries into a bounded queue. Repeated movement
/// coalesces, but the first frame, contact changes and lifts retain their order.
final class WorkspaceTouchMailbox: @unchecked Sendable {
    private struct State {
        var generation: UInt64 = 0
        var frames: [WorkspaceTouchFrame] = []
        var scheduled = false
        var received = 0
        var lastContactByDevice: [UInt64: WorkspaceTouchFrame] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func activate(_ generation: UInt64) {
        state.withLock { $0 = State(generation: generation) }
    }

    func offer(_ frame: WorkspaceTouchFrame, generation: UInt64) -> Bool {
        state.withLock { value in
            guard generation != 0, value.generation == generation else { return false }
            value.received += 1
            let previous = value.lastContactByDevice.updateValue(frame, forKey: frame.device)
            // One/two-finger motion belongs to apps; avoid a main-queue hop per frame.
            if (0..<3).contains(frame.fingers), let previous,
               previous.fingers == frame.fingers, previous.contacts == frame.contacts { return false }
            let sameContact: (WorkspaceTouchFrame) -> Bool = {
                $0.device == frame.device && $0.fingers == frame.fingers && $0.contacts == frame.contacts
            }
            if value.frames.count >= 2,
               sameContact(value.frames[value.frames.count - 1]),
               sameContact(value.frames[value.frames.count - 2]) {
                value.frames[value.frames.count - 1] = frame
            } else if value.frames.count >= 32 {
                value.frames = [WorkspaceTouchFrame(device: frame.device, fingers: -1, x: 0, y: 0,
                                                    timestamp: frame.timestamp, contacts: 0), frame]
            } else { value.frames.append(frame) }
            guard !value.scheduled else { return false }
            value.scheduled = true
            return true
        }
    }

    func take() -> (generation: UInt64, frames: [WorkspaceTouchFrame], received: Int) {
        state.withLock { value in
            let frames = value.frames
            value.frames.removeAll(keepingCapacity: true)
            value.scheduled = false
            return (value.generation, frames, value.received)
        }
    }
}

@MainActor
final class RawWorkspaceTouchSource: ObservableObject {
    static let shared = RawWorkspaceTouchSource()
    nonisolated static let mailbox = WorkspaceTouchMailbox()
    @Published private(set) var status = "Disabled"
    @Published private(set) var maximumFingerCount = 0
    private(set) var deviceCount = 0
    private(set) var frameCount = 0
    private var generation: UInt64 = 0
    private var notifications: [(NotificationCenter, NSObjectProtocol)] = []
    private var revalidation: Task<Void, Never>?
    private var suspended = false
    var onFrame: ((WorkspaceTouchFrame) -> Void)?

    func syncConfiguration() {
        stop()
        guard config.workspaceSwipe.enabled, !isUnitTest else { return }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, sleeping: false)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification, sleeping: true)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification, sleeping: true)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification, sleeping: false)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification, sleeping: false)
        _ = winmux_touch_watch_topology {
            MainActor.assumeIsolated { RawWorkspaceTouchSource.shared.scheduleRevalidation() }
        }
        startDevices()
    }

    func stop() {
        revalidation?.cancel()
        revalidation = nil
        generation &+= 1
        Self.mailbox.activate(0)
        if !isUnitTest { winmux_touch_stop(); winmux_touch_unwatch_topology() }
        for (center, token) in notifications { center.removeObserver(token) }
        notifications.removeAll()
        deviceCount = 0
        frameCount = 0
        maximumFingerCount = 0
        suspended = false
        status = "Disabled"
    }

    private func startDevices() {
        guard config.workspaceSwipe.enabled, !suspended else { return }
        generation &+= 1
        Self.mailbox.activate(generation)
        frameCount = 0
        maximumFingerCount = 0
        let count = winmux_touch_start(generation, workspaceTouchFrameCallback)
        deviceCount = max(0, Int(count))
        status = count < 0 ? "Raw touch API unavailable" : count == 0 ? "No trackpad registered" : "Listening on \(count) trackpad(s)"
    }

    fileprivate func drain() {
        let batch = Self.mailbox.take()
        guard batch.generation == generation, !suspended, config.workspaceSwipe.enabled else { return }
        frameCount = batch.received
        for frame in batch.frames {
            if frame.fingers > maximumFingerCount { maximumFingerCount = frame.fingers }
            onFrame?(frame)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, sleeping: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                WorkspaceSwipeController.shared.reset()
                if sleeping {
                    self.suspended = true
                    self.revalidation?.cancel()
                    self.generation &+= 1
                    Self.mailbox.activate(0)
                    winmux_touch_stop()
                    self.deviceCount = 0
                    self.status = "Paused while sleeping"
                } else {
                    self.suspended = false
                    self.scheduleRevalidation()
                }
            }
        }
        notifications.append((center, token))
    }

    private func scheduleRevalidation() {
        guard config.workspaceSwipe.enabled, !suspended else { return }
        revalidation?.cancel()
        revalidation = Task { @MainActor [weak self] in
            // Allow Bluetooth and built-in devices to settle after topology changes.
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self, !Task.isCancelled, config.workspaceSwipe.enabled, !self.suspended else { return }
            WorkspaceSwipeController.shared.reset()
            self.startDevices()
            self.revalidation = nil
        }
    }
}

// A C callback must not inherit the main actor from startDevices(). The driver
// calls this function on its own thread; only copied data and the locked mailbox
// are touched until an explicit hop to the main queue.
nonisolated func workspaceTouchFrameCallback(_ generation: UInt64, _ device: UInt64, _ fingers: Int32,
                                             _ x: Double, _ y: Double, _ timestamp: Double, _ contacts: UInt64) {
    let frame = WorkspaceTouchFrame(device: device, fingers: Int(fingers), x: x, y: y,
                                   timestamp: timestamp, contacts: contacts)
    guard RawWorkspaceTouchSource.mailbox.offer(frame, generation: generation) else { return }
    DispatchQueue.main.async { RawWorkspaceTouchSource.shared.drain() }
}
