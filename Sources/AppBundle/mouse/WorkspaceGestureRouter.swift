import AppKit

/// Locks a contact sequence to one axis. The horizontal recognizer retains its existing thresholds.
struct WorkspaceGestureAxisRouter {
    enum Axis { case horizontal, vertical }
    private var anchor: WorkspaceTouchFrame?
    private(set) var axis: Axis?
    private var rejected = false
    var isRejected: Bool { rejected }

    mutating func route(_ frame: WorkspaceTouchFrame) -> (Axis, [WorkspaceTouchFrame])? {
        if let anchor, anchor.device != frame.device { return nil }
        defer { if frame.fingers == 0 { self = Self() } }
        if let axis { return (axis, [frame]) }
        guard !rejected else { return nil }
        guard frame.fingers == 3, frame.x.isFinite, frame.y.isFinite,
              frame.timestamp.isFinite, (0...1).contains(frame.x), (0...1).contains(frame.y) else {
            if anchor != nil || frame.fingers > 3 || frame.fingers < 0 { rejected = true }
            return nil
        }
        guard let anchor else { self.anchor = frame; return nil }
        guard frame.contacts == anchor.contacts, frame.timestamp >= anchor.timestamp,
              frame.timestamp - anchor.timestamp <= 10 else { rejected = true; return nil }
        let dx = abs(frame.x - anchor.x), dy = abs(frame.y - anchor.y)
        if dx >= 0.02, dx >= dy * 1.5 { axis = .horizontal }
        else if dy >= 0.04, dy >= dx * 1.5 { axis = .vertical }
        guard let axis else { return nil }
        return (axis, [anchor, frame])
    }
}

enum WorkspaceHorizontalGestureRoute: Equatable {
    case workspaceSwipe, scrolling, ignore

    static func resolve(optionHeldAtStart: Bool, scrollingEnabledAtStart: Bool) -> Self {
        guard optionHeldAtStart else { return .workspaceSwipe }
        return scrollingEnabledAtStart ? .scrolling : .ignore
    }
}

@MainActor
struct WorkspaceGestureRouterDependencies {
    var horizontalEnabled: () -> Bool
    var overviewEnabled: () -> Bool
    var overviewIsOpen: () -> Bool
    var horizontal: (WorkspaceTouchFrame) -> Void
    var show: () -> Void
    var hide: () -> Void
    var beginOverviewGesture: ((Bool, Double) -> Bool)? = nil
    var updateOverviewGesture: ((Double) -> Void)? = nil
    var endOverviewGesture: ((Bool, Double) -> Void)? = nil
    static var live: Self {
        Self(horizontalEnabled: { config.workspaceSwipe.enabled },
             overviewEnabled: { config.workspaceOverview.threeFingerUp },
             overviewIsOpen: { WorkspaceOverviewController.shared.isOpen },
             horizontal: { WorkspaceSwipeController.shared.handle($0) },
             show: { _ = WorkspaceOverviewController.shared.show() },
             hide: { WorkspaceOverviewController.shared.dismiss() },
             beginOverviewGesture: { WorkspaceOverviewController.shared.beginGesture(opening: $0, progress: $1) },
             updateOverviewGesture: { WorkspaceOverviewController.shared.updateGesture(progress: $0) },
             endOverviewGesture: { WorkspaceOverviewController.shared.endGesture(commit: $0, velocity: $1) })
    }
}

@MainActor
final class WorkspaceGestureRouter {
    static let shared = WorkspaceGestureRouter()
    private var axes = WorkspaceGestureAxisRouter()
    private var vertical = WorkspaceTouchRecognizer()
    private var opens = false
    private var eligible = false
    private var verticalProgress = 0.0
    private var interactive = false
    private var sampleTime = 0.0
    private var velocity = 0.0
    private var sequenceStarted = false
    private var optionLatched = false
    private var scrollingEnabledAtStart = false
    private var contactDeviceAtStart: UInt64?
    private weak var scrollingWorkspaceAtStart: Workspace?
    private var scrollingMonitorPointAtStart: CGPoint?
    private var scrollingOffsetAtStart: CGFloat?
    private var scrollingTopologyAtStart: String?
    private var scrollingEpochAtStart: UInt64?
    private let dependencies: WorkspaceGestureRouterDependencies

    init(dependencies: WorkspaceGestureRouterDependencies = .live) { self.dependencies = dependencies }

    /// What a touch sequence latched at its start, cleared when its fingers lift.
    private func clearSequenceState() {
        sequenceStarted = false
        optionLatched = false
        scrollingEnabledAtStart = false
        scrollingWorkspaceAtStart = nil
        scrollingMonitorPointAtStart = nil
        scrollingOffsetAtStart = nil
        scrollingTopologyAtStart = nil
        scrollingEpochAtStart = nil
    }

    func reset() {
        let cancelsInteraction = interactive
        interactive = false
        axes = WorkspaceGestureAxisRouter()
        vertical = WorkspaceTouchRecognizer()
        eligible = false
        verticalProgress = 0
        velocity = 0
        clearSequenceState()
        contactDeviceAtStart = nil
        WorkspaceScrollingGestureController.shared.reset()
        if cancelsInteraction { dependencies.endOverviewGesture?(false, 0) }
    }

    func handle(_ frame: WorkspaceTouchFrame) {
        defer { if frame.fingers == 0 { WorkspaceScrollingGestureController.shared.contactsEnded() } }
        if !sequenceStarted, frame.fingers == 3 {
            sequenceStarted = true
            contactDeviceAtStart = frame.device
            optionLatched = NSEvent.modifierFlags.contains(.option)
            let pointer = mouseLocation
            if let monitor = sortedMonitors.first(where: { $0.rect.contains(pointer) }) {
                scrollingMonitorPointAtStart = monitor.rect.topLeftCorner
                scrollingWorkspaceAtStart = monitor.activeWorkspace
                scrollingEnabledAtStart = monitor.activeWorkspace.arrangement == .scrolling
                if scrollingEnabledAtStart {
                    scrollingOffsetAtStart = monitor.activeWorkspace.scrollingMetrics.clampedOffset(monitor.activeWorkspace.scrollingOffset)
                    scrollingTopologyAtStart = monitor.activeWorkspace.scrollingTopologySignature
                    scrollingEpochAtStart = monitor.activeWorkspace.scrollingSessionEpoch
                }
            }
        }
        if sequenceStarted, optionLatched, frame.device != contactDeviceAtStart {
            WorkspaceScrollingGestureController.shared.reset()
            if frame.fingers == 0 { reset() }
            return
        }
        guard let (axis, frames) = axes.route(frame) else {
            if axes.isRejected { WorkspaceScrollingGestureController.shared.reset() }
            if frame.fingers == 0 {
                WorkspaceScrollingGestureController.shared.reset(commit: true)
                clearSequenceState()
            }
            return
        }
        switch axis {
        case .horizontal:
            switch WorkspaceHorizontalGestureRoute.resolve(optionHeldAtStart: optionLatched,
                                                            scrollingEnabledAtStart: scrollingEnabledAtStart) {
            case .scrolling:
                WorkspaceScrollingGestureController.shared.handle(frames,
                    capturedWorkspace: scrollingWorkspaceAtStart,
                    capturedMonitorPoint: scrollingMonitorPointAtStart,
                    capturedOffset: scrollingOffsetAtStart,
                    capturedTopology: scrollingTopologyAtStart,
                    capturedEpoch: scrollingEpochAtStart)
                if frame.fingers == 0 {
                    clearSequenceState()
                }
                return
            case .ignore:
                if frame.fingers == 0 {
                    clearSequenceState()
                }
                return
            case .workspaceSwipe:
                break
            }
            guard dependencies.horizontalEnabled(), !dependencies.overviewIsOpen() else { return }
            for item in frames { dependencies.horizontal(item) }
        case .vertical:
            for item in frames {
                let transformed = WorkspaceTouchFrame(device: item.device, fingers: item.fingers,
                    x: 1 - item.y, y: item.x, timestamp: item.timestamp, contacts: item.contacts)
                guard let event = vertical.receive(transformed, displayPoint: .zero, reversed: false) else { continue }
                switch event {
                case .began(let request):
                    opens = request.isNext
                    verticalProgress = request.progress
                    eligible = opens ? dependencies.overviewEnabled() && !dependencies.overviewIsOpen()
                        : dependencies.overviewIsOpen()
                    sampleTime = item.timestamp
                    velocity = 0
                    interactive = eligible && (dependencies.beginOverviewGesture?(opens, request.progress) ?? false)
                case .ended(let commit):
                    // Dismissal is always available for an open overview, including
                    // command-opened sessions with the upward shortcut disabled.
                    let commits = commit || (!opens && verticalProgress >= 0.25)
                    let enabled = !opens || dependencies.overviewEnabled()
                    let wasInteractive = interactive
                    interactive = false
                    let wasEligible = eligible
                    eligible = false
                    if wasInteractive {
                        let speed = item.timestamp - sampleTime < 0.08 ? velocity : 0
                        dependencies.endOverviewGesture?(commits && wasEligible && enabled, speed)
                    } else if commits && wasEligible && enabled && opens != dependencies.overviewIsOpen() {
                        if opens { dependencies.show() }
                        else { dependencies.hide() }
                    }
                case .cancelled:
                    let wasInteractive = interactive
                    interactive = false; eligible = false
                    if wasInteractive { dependencies.endOverviewGesture?(false, 0) }
                case .changed(let progress):
                    let dt = item.timestamp - sampleTime
                    velocity = dt > 0 && dt <= 0.1 ? (progress - verticalProgress) / dt : 0
                    sampleTime = item.timestamp
                    verticalProgress = progress
                    if interactive {
                        dependencies.updateOverviewGesture?(progress)
                        WorkspaceMotionDiagnostics.record("Overview callback to layer submission", milliseconds: max(0, (CACurrentMediaTime() - item.receivedAt) * 1000))
                    }
                }
            }
        }
        if frame.fingers == 0 {
            clearSequenceState()
        }
    }
}
