import AppKit
import os
import PrivateApi

/// Parking is confirmed from native geometry, never from a cached visibility flag.
func workspaceParkingPositionMatches(_ observed: CGPoint, _ requested: CGPoint) -> Bool {
    abs(observed.x - requested.x) <= 2 && abs(observed.y - requested.y) <= 2
}

/// A failed or superseded reveal must not publish the window as visible.
struct WorkspaceWindowRevealState {
    enum Phase { case visible, parked, restoring }
    private(set) var phase: Phase = .visible
    private(set) var generation: UInt64 = 0

    mutating func park() {
        generation &+= 1
        phase = .parked
    }

    mutating func begin() -> UInt64 {
        generation &+= 1
        phase = .restoring
        return generation
    }

    mutating func finish(_ token: UInt64, succeeded: Bool) -> Bool {
        guard token == generation, phase == .restoring else { return false }
        phase = succeeded ? .visible : .parked
        return succeeded
    }
}

@MainActor
enum WorkspaceTransitionDiagnostics {
    static let enabled = ProcessInfo.processInfo.environment["WINMUXX_TRACE_WORKSPACE_TRANSITIONS"] == "1"
    private static let logger = Logger(subsystem: "com.gfavaro.winmuxx", category: "workspace-transition")

    static func record(_ stage: String, window: MacWindow, generation: UInt64, requested: CGRect? = nil) {
        guard enabled else { return }
        var actual = CGRect.zero
        let observed = winmuxFrame(window.windowId, &actual)
        let monitor = window.nodeMonitor.map { String(describing: $0.rect.topLeftCorner) } ?? "none"
        let requestedFrame = requested.map { String(describing: $0) } ?? "none"
        let message = "t=\(ProcessInfo.processInfo.systemUptime) stage=\(stage) window=\(window.windowId) generation=\(generation) workspace=\(window.nodeWorkspace?.name ?? "none") monitor=\(monitor) requested=\(requestedFrame) actual=\(observed ? String(describing: actual) : "unavailable")"
        logger.notice("\(message, privacy: .public)")
    }
}

private func winmuxFrame(_ id: UInt32, _ frame: inout CGRect) -> Bool {
    winmux_window_frame(id, &frame)
}

/// Runs on the app's AX thread. Extra observations are diagnostic-only.
enum WorkspaceFrameWriteDiagnostics {
    static let enabled = ProcessInfo.processInfo.environment["WINMUXX_TRACE_WORKSPACE_TRANSITIONS"] == "1"
    private static let logger = Logger(subsystem: "com.gfavaro.winmuxx", category: "workspace-frame-write")

    static func record(_ stage: String, id: UInt32, window: AXUIElement, positionFirst: Bool,
                       requestedPosition: CGPoint?, requestedSize: CGSize?, accepted: Bool? = nil) {
        guard enabled else { return }
        let position = window.get(Ax.topLeftCornerAttr)
        let size = window.get(Ax.sizeAttr)
        var native = CGRect.zero
        let observed = winmuxFrame(id, &native)
        let message = "t=\(ProcessInfo.processInfo.systemUptime) stage=\(stage) window=\(id) positionFirst=\(positionFirst) requestedPosition=\(String(describing: requestedPosition)) requestedSize=\(String(describing: requestedSize)) accepted=\(String(describing: accepted)) axPosition=\(String(describing: position)) axSize=\(String(describing: size)) native=\(observed ? String(describing: native) : "unavailable")"
        logger.notice("\(message, privacy: .public)")
    }
}
