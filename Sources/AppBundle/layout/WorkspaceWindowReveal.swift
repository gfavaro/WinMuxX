import AppKit
import os
import PrivateApi

enum OptimalHideCorner { case bottomLeftCorner, bottomRightCorner }

func workspaceParkingPoint(corner: OptimalHideCorner, visibleRect: CGRect, windowSize: CGSize, zeroOffset: Bool) -> CGPoint {
    let offset: CGFloat = zeroOffset ? 0 : 1
    switch corner {
    case .bottomLeftCorner: return CGPoint(x: visibleRect.minX - windowSize.width + offset, y: visibleRect.maxY - offset)
    case .bottomRightCorner: return CGPoint(x: visibleRect.maxX - offset, y: visibleRect.maxY - offset)
    }
}

/// macOS can clamp a bottom-corner request upward to keep native chrome reachable.
/// Accept only a bounded correction with at most the existing one-point parking
/// strip visible on every display. Meaningful drift onscreen must still be repaired.
func workspaceParkingFrameIsAcceptable(_ observed: CGRect, requested: CGPoint, displays: [CGRect]) -> Bool {
    guard [observed.minX, observed.minY, observed.width, observed.height, requested.x, requested.y].allSatisfy(\.isFinite),
          observed.width > 0, observed.height > 0, !displays.isEmpty,
          abs(observed.minX - requested.x) <= 64, abs(observed.minY - requested.y) <= 64 else { return false }
    return displays.allSatisfy { display in
        guard [display.minX, display.minY, display.width, display.height].allSatisfy(\.isFinite),
              display.width > 0, display.height > 0 else { return false }
        let visible = observed.intersection(display)
        return visible.isNull || visible.width <= 1 || visible.height <= 1
    }
}

/// Whether a parked window must be parked again. The first park is not counted. An app that
/// keeps pulling its window back from the corner (iPhone Mirroring keeps part of itself on
/// screen) would otherwise be re-parked on every refresh its own move causes, a loop of
/// refreshes; it gets the same bounded tries as a tiled window its app keeps moving.
func workspaceShouldRepark(
    parked: CGRect?, requested: CGPoint, displays: [CGRect],
    budget: inout FrameRecoveryBudget, now: ContinuousClock.Instant = .now,
) -> Bool {
    guard let parked else { return true }
    if workspaceParkingFrameIsAcceptable(parked, requested: requested, displays: displays) { return false }
    let target = Rect(topLeftX: requested.x, topLeftY: requested.y, width: parked.width, height: parked.height)
    return budget.shouldReapply(tile: target, resting: false, now: now)
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

    static func recordNativeEvent(_ event: UInt32, windowId: UInt32) {
        guard enabled, let window = MacWindow.allWindowsMap[windowId] else { return }
        let candidate = HiddenWorkspaceWindowRecoveryDependencies.live.isHiddenInactive(windowId)
        let state = "event=\(event) candidate=\(candidate) parked=\(window.isHiddenInCorner) completed=\(window.hasCompletedNativeParking) fullscreen=\(String(describing: window.lastKnownNativeFullscreen)) minimized=\(String(describing: window.lastKnownNativeMinimized)) focused=\(focus.windowOrNil?.windowId ?? 0) missionControl=\(WindowBorderController.shared.isMissionControlActive)"
        record("native-geometry \(state)", window: window, generation: 0)
    }

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

/// Prefer the corner whose parking probes overlap fewer neighboring displays.
func optimalWorkspaceHideCorner(for display: Rect, displays: [Rect]) -> OptimalHideCorner {
    let horizontalProbeOffset = display.width * 0.1
    let verticalProbeOffset = display.height * 0.1
    let exactCornerProbeWeight = 10
    func score(_ corner: CGPoint, outward: CGFloat) -> Int {
        let horizontalProbe = corner + CGPoint(x: outward * 2, y: -verticalProbeOffset)
        let verticalProbe = corner + CGPoint(x: -outward * horizontalProbeOffset, y: 2)
        let exactCornerProbe = corner + CGPoint(x: outward * 2, y: 2)
        return displays.sumOfInt { rect in
            (rect.contains(horizontalProbe) ? 1 : 0) + (rect.contains(verticalProbe) ? 1 : 0) +
                exactCornerProbeWeight * (rect.contains(exactCornerProbe) ? 1 : 0)
        }
    }
    return score(display.bottomLeftCorner, outward: -1) < score(display.bottomRightCorner, outward: 1)
        ? .bottomLeftCorner : .bottomRightCorner
}
