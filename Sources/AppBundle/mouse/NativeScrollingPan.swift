import AppKit
import Common

/// Native scrolling pans read the same raw trackpad touches as virtual mode and feed the
/// same WorkspaceScrollingGestureController, so tracking, velocity and the settling
/// spring are identical. macOS keeps three- and four-finger swipes for Spaces, so a
/// native pan is Option + two fingers, latched when the fingers touch down over a
/// visible scrolling desktop. A vertical two-finger move stays an ordinary scroll.
@MainActor
final class NativeScrollingTouchRouter {
    static let shared = NativeScrollingTouchRouter()
    private var axes = WorkspaceGestureAxisRouter(fingers: 2)
    private var started = false
    private(set) var ownsGesture = false
    /// Why the last two-finger touch did or did not become a pan, for doctor.
    private(set) var lastDecision = "none"
    /// Finger counts of the last touch sequence, run-length encoded, for doctor.
    private(set) var lastTrace = "none"
    private var trace: [(fingers: Int, count: Int)] = []
    private var traceAnchor: WorkspaceTouchFrame?
    private var device: UInt64?
    private weak var workspace: Workspace?
    private var monitorPoint: CGPoint?
    private var offset: CGFloat?
    private var topology: String?
    private var epoch: UInt64?
    var optionOnly: () -> Bool = { NSEvent.modifierFlags.intersection([.option, .command, .control, .shift]) == .option }
    var pointer: () -> CGPoint = { mouseLocation }
    var controller = WorkspaceScrollingGestureController.shared

    func handle(_ frame: WorkspaceTouchFrame) {
        record(frame)
        defer { if frame.fingers == 0 { controller.contactsEnded(); clear() } }
        if !started, frame.fingers == 2 {
            started = true
            device = frame.device
            capture()
        }
        guard ownsGesture else { return }
        if frame.device != device { controller.reset(); ownsGesture = false; return }
        guard let (axis, frames) = axes.route(frame) else {
            if axes.isRejected {
                controller.reset(); ownsGesture = false
                let moved = traceAnchor.map { String(format: "dx %.3f dy %.3f", frame.x - $0.x, frame.y - $0.y) } ?? "no anchor"
                lastDecision = "rejected at \(frame.fingers) fingers, contacts " +
                    "\(frame.contacts == traceAnchor?.contacts ? "same" : "changed"), \(moved)"
            }
            if frame.fingers == 0 { controller.reset(commit: true) }
            return
        }
        guard axis == .horizontal else { ownsGesture = false; lastDecision = "vertical: left to macOS"; return }
        controller.handle(frames, capturedWorkspace: workspace, capturedMonitorPoint: monitorPoint,
            capturedOffset: offset, capturedTopology: topology, capturedEpoch: epoch)
        lastDecision = controller.isMotionActive ? "panning" : "declined by the gesture controller (ready \(isWinMuxRuntimeReady), " +
            "mouse manipulation \(isMouseManipulationActive), button down \(isLeftMouseButtonDown), " +
            "Mission Control \(WindowBorderController.shared.isMissionControlActive), " +
            "same desktop \(workspace?.scrollingTopologySignature == topology && workspace?.scrollingSessionEpoch == epoch))"
    }

    private func capture() {
        let point = pointer()
        guard config.scrolling.gestureEnabled else { lastDecision = "scrolling gestures are disabled in config"; return }
        guard runtime.workspaceBackend.nativeTilingEnabled else { lastDecision = "native tiling is off"; return }
        guard optionOnly() else { lastDecision = "Option was not held alone when the fingers touched down"; return }
        guard let monitor = sortedMonitors.first(where: { $0.rect.contains(point) }) else {
            lastDecision = "pointer is not on a display"; return
        }
        let target = monitor.activeWorkspace
        guard target.arrangement == .scrolling, target.isVisible else {
            lastDecision = "desktop under the pointer is not scrolling"; return
        }
        lastDecision = "latched; waiting for horizontal movement"
        workspace = target
        monitorPoint = monitor.rect.topLeftCorner
        offset = target.scrollingMetrics.clampedOffset(target.scrollingOffset)
        topology = target.scrollingTopologySignature
        epoch = target.scrollingSessionEpoch
        ownsGesture = true
    }

    private func record(_ frame: WorkspaceTouchFrame) {
        if traceAnchor == nil, frame.fingers == 2 { traceAnchor = frame }
        if let last = trace.last, last.fingers == frame.fingers { trace[trace.count - 1].count += 1 }
        else if trace.count < 40 { trace.append((frame.fingers, 1)) }
        guard frame.fingers == 0 else { return }
        lastTrace = trace.map { $0.count > 1 ? "\($0.fingers)x\($0.count)" : "\($0.fingers)" }.joined(separator: " ")
        trace = []
        traceAnchor = nil
    }

    private func clear() {
        axes = WorkspaceGestureAxisRouter(fingers: 2)
        started = false
        ownsGesture = false
        device = nil
        workspace = nil
        monitorPoint = nil
        offset = nil
        topology = nil
        epoch = nil
    }
}

/// Swallows the scroll events of a native pan, including the momentum that follows
/// lifting the fingers, so the app under the pointer does not scroll as well.
@MainActor
final class NativeScrollingPan {
    static let shared = NativeScrollingPan()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var consuming = false

    func start() {
        guard tap == nil, !isUnitTest else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated { NativeScrollingPan.shared.reenable() }
                    return Unmanaged.passUnretained(event)
                }
                let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
                let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
                let consumed = MainActor.assumeIsolated {
                    NativeScrollingPan.shared.consumes(phase: phase, momentumPhase: momentum,
                        panning: NativeScrollingTouchRouter.shared.ownsGesture)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: nil) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    /// Momentum phase 3 ends the trailing momentum of a consumed scroll.
    func consumes(phase: Int64, momentumPhase: Int64, panning: Bool) -> Bool {
        if panning { consuming = true; return true }
        guard consuming else { return false }
        if momentumPhase == 0, phase == 1 || phase == 128 { consuming = false; return false } // A new scroll.
        if momentumPhase == 3 { consuming = false }
        return true
    }
}
