import AppKit
import QuartzCore

/// Fingers in a scrolling pan: macOS keeps three for Spaces in native mode.
@MainActor func scrollingPanFingerCount() -> Int { runtime.workspaceBackend.kind == .native ? 2 : 3 }

@MainActor
struct ScrollingGestureDependencies {
    var eligible: () -> Bool = {
        isWinMuxRuntimeReady && TrayMenuModel.shared.isEnabled && !isMouseManipulationActive &&
            !isLeftMouseButtonDown && !WorkspaceOverviewController.shared.isOpen &&
            !WindowBorderController.shared.isMissionControlActive
    }
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var nextFrame: () async throws -> Void = { try await Task.sleep(for: .milliseconds(16)) }
}

struct ScrollingGestureContactGate {
    private(set) var rejectedUntilLift = false
    mutating func interrupt() { rejectedUntilLift = true }
    mutating func allows(_ frame: WorkspaceTouchFrame) -> Bool {
        if frame.fingers == 0 { rejectedUntilLift = false; return false }
        return !rejectedUntilLift
    }
}

@MainActor
final class WorkspaceScrollingGestureController {
    static let shared = WorkspaceScrollingGestureController()
    private weak var workspace: Workspace?
    private var anchor: WorkspaceTouchFrame?
    private var lastFrame: WorkspaceTouchFrame?
    private var startOffset: CGFloat = 0
    private var lastDirection: CGFloat = 0
    private var lastOffsetVelocity: CGFloat = 0
    private var monitorWidth: CGFloat = 0
    private var monitorPoint: CGPoint?
    private var topology: String?
    private var ownerEpoch: UInt64?
    private var sessionGeneration: UInt64 = 0
    private var settleTask: Task<Void, Never>?
    var settlementCompletion: Task<Void, Never>? { settleTask }
    private(set) var isMotionActive = false
    private var contactGate = ScrollingGestureContactGate()
    private let dependencies: ScrollingGestureDependencies

    init(dependencies: ScrollingGestureDependencies = .init()) { self.dependencies = dependencies }

    func contactsEnded() {
        _ = contactGate.allows(.init(device: 0, fingers: 0, x: 0, y: 0, timestamp: 0, contacts: 0))
    }

    func reset(commit: Bool = false) {
        contactGate.interrupt()
        if anchor == nil {
            if commit { return }
            cancelSettlement(keepOffset: true)
            clear()
            return
        }
        guard let workspace, anchor != nil else { cancelSettlement(keepOffset: true); clear(); return }
        guard sessionIsCurrent(workspace) else { cancelSettlement(keepOffset: true); clear(); return }
        if commit {
            settle(workspace)
            anchor = nil
            WorkspaceScrollingMinimap.shared.endGesture()
        }
        else {
            workspace.scrollingOffset = startOffset
            scheduleRefreshSession(.globalObserver("scrollingGestureCancelled"))
            clear()
        }
    }

    /// A click or keyboard focus owns the viewport immediately and leaves it at
    /// the current scalar position; the subsequent layout reveals the new focus.
    func interruptForExplicitFocus() {
        if anchor != nil || settleTask != nil { contactGate.interrupt() }
        cancelSettlement(keepOffset: true)
        if let workspace { workspace.scrollingGestureMotionActive = false }
        clear()
        isMotionActive = false
        WorkspaceScrollingMinimap.shared.endGesture()
    }

    func cancelForInteractiveDrag() {
        guard isMotionActive else { return }
        abandon()
    }

    func cancelForMonitorOwnershipChange(_ point: CGPoint) {
        guard monitorPoint == point else { return }
        abandon()
    }

    func cancelForWorkspaceChange(_ workspace: Workspace) {
        guard self.workspace === workspace else { return }
        abandon()
    }

    func handle(_ frames: [WorkspaceTouchFrame], capturedWorkspace: Workspace?, capturedMonitorPoint: CGPoint?,
                capturedOffset: CGFloat?, capturedTopology: String?, capturedEpoch: UInt64?) {
        for frame in frames {
            if frame.fingers == 0 {
                reset(commit: true)
                _ = contactGate.allows(frame)
                continue
            }
            guard contactGate.allows(frame) else { continue }
            if frame.fingers < 0 { contactGate.interrupt(); reset(); continue }
            if frame.fingers < scrollingPanFingerCount() {
                reset(commit: true)
                continue
            }
            if anchor == nil {
                guard begin(at: frame, workspace: capturedWorkspace, monitorPoint: capturedMonitorPoint,
                            offset: capturedOffset, topology: capturedTopology, epoch: capturedEpoch) else { contactGate.interrupt(); continue }
            }
            guard let anchor, let workspace, workspace.arrangement == .scrolling,
                  frame.device == anchor.device, frame.contacts == anchor.contacts,
                  frame.fingers == scrollingPanFingerCount(), frame.x.isFinite, frame.y.isFinite,
                  (0...1).contains(frame.x), (0...1).contains(frame.y),
                  frame.timestamp.isFinite, frame.timestamp >= anchor.timestamp,
                  frame.timestamp - anchor.timestamp <= 10,
                  lastFrame.map({ frame.timestamp >= $0.timestamp }) ?? true else { contactGate.interrupt(); reset(); continue }
            guard sessionIsCurrent(workspace) else { contactGate.interrupt(); abandon(); continue }
            let previous = lastFrame ?? anchor
            let dx = CGFloat(frame.x - previous.x)
            let scale = monitorWidth / 0.24 * CGFloat(config.scrolling.gestureSensitivity)
            let reversed = config.workspaceSwipe.reverseDirection
            let offsetDelta = -dx * scale * (reversed ? -1 : 1)
            let metrics = workspace.scrollingMetrics
            let current = metrics.clampedOffset(workspace.scrollingOffset)
            let next = metrics.clampedOffset(current + offsetDelta)
            if next != current {
                let applied = next - current
                lastDirection = applied > 0 ? 1 : -1
                let dt = frame.timestamp - previous.timestamp
                lastOffsetVelocity = dt > 0 && dt <= 0.1 ? applied / CGFloat(dt) : 0
            }
            workspace.scrollingOffset = next
            lastFrame = frame
            workspace.scrollingGestureMotionActive = true
            isMotionActive = true
            scheduleRefreshSession(.globalObserver("scrollingGesture"))
            WorkspaceScrollingMinimap.shared.show(workspace, duringGesture: true)
        }
    }

    private func begin(at frame: WorkspaceTouchFrame, workspace captured: Workspace?, monitorPoint: CGPoint?,
                       offset capturedOffset: CGFloat?, topology capturedTopology: String?, epoch capturedEpoch: UInt64?) -> Bool {
        guard config.scrolling.gestureEnabled, dependencies.eligible(),
              frame.fingers == scrollingPanFingerCount(), frame.x.isFinite, frame.y.isFinite, frame.timestamp.isFinite,
              (0...1).contains(frame.x), (0...1).contains(frame.y),
              let point = monitorPoint, let workspace = captured,
              workspace.arrangement == .scrolling, workspace.isVisible,
              let capturedOffset, capturedOffset.isFinite,
              let capturedTopology, capturedTopology == workspace.scrollingTopologySignature,
              let capturedEpoch, capturedEpoch == workspace.scrollingSessionEpoch,
              let monitor = sortedMonitors.first(where: { $0.rect.topLeftCorner == point }),
              monitor.activeWorkspace === workspace else { return false }
        cancelSettlement(keepOffset: true)
        self.workspace = workspace
        anchor = frame
        startOffset = workspace.scrollingMetrics.clampedOffset(capturedOffset)
        workspace.scrollingOffset = startOffset
        monitorWidth = monitor.rect.width
        self.monitorPoint = point
        topology = capturedTopology
        ownerEpoch = capturedEpoch
        lastFrame = frame
        lastOffsetVelocity = 0
        lastDirection = 0
        sessionGeneration &+= 1
        workspace.scrollingGestureSessionID = UUID()
        workspace.scrollingGestureMotionActive = true
        isMotionActive = true
        WorkspaceScrollingMinimap.shared.show(workspace, duringGesture: true)
        return true
    }

    private func sessionIsCurrent(_ workspace: Workspace) -> Bool {
        guard self.workspace === workspace, workspace.isVisible,
              workspace.arrangement == .scrolling,
              workspace.scrollingSessionEpoch == ownerEpoch,
              workspace.scrollingTopologySignature == topology,
              let monitorPoint,
              workspace.workspaceMonitor.rect.topLeftCorner == monitorPoint,
              let monitor = sortedMonitors.first(where: { $0.rect.topLeftCorner == monitorPoint }),
              monitor.activeWorkspace === workspace else { return false }
        return true
    }

    private func settle(_ workspace: Workspace) {
        let metrics = workspace.scrollingMetrics
        guard let chosen = nearestColumn(in: metrics) else {
            workspace.scrollingGestureMotionActive = false
            scheduleRefreshSession(.globalObserver("scrollingGestureSettled"))
            clear()
            return
        }
        let destination = metrics.revealedOffset(for: chosen, current: workspace.scrollingOffset)
        let selected = chosen.node.mostRecentWindowRecursive
        workspace.lastScrollingFocusWindowId = selected?.windowId
        workspace.scrollingAnchorWindowId = selected?.windowId
        workspace.captureScrollingViewportAnchor(using: metrics, preferredWindow: selected)
        let generation = sessionGeneration
        guard let duration = WorkspaceGestureAnimation.duration(milliseconds: config.workspaceSwipe.animationDurationMs,
            enabled: config.animations.enabled, reduceMotion: dependencies.reduceMotion()),
            abs(destination - workspace.scrollingOffset) > 0.5 else {
            workspace.scrollingOffset = destination
            workspace.scrollingGestureMotionActive = false
            isMotionActive = false
            scheduleRefreshSession(.globalObserver("scrollingGestureSettled"))
            clear()
            if let selected { focusSettledScrollingWindow(selected) }
            WorkspaceScrollingMinimap.shared.show(workspace)
            return
        }

        let from = workspace.scrollingOffset
        let spring = WorkspaceGestureAnimation.settlingAnimation(keyPath: "position.x", from: from,
            to: destination, speed: Double(lastOffsetVelocity), duration: duration)
        let scalarSpring = WorkspaceGestureScalarSpring(from: from, to: destination, animation: spring)
        let settlingDuration = max(spring.settlingDuration, 0.05)
        workspace.scrollingGestureMotionActive = true
        isMotionActive = true
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self, weak workspace] in
            guard let self else { return }
            let started = self.dependencies.now()
            while !Task.isCancelled, self.dependencies.now() - started < settlingDuration {
                guard let workspace, self.sessionGeneration == generation else { return }
                guard self.sessionIsCurrent(workspace) else { self.abandon(); return }
                let elapsed = self.dependencies.now() - started
                let scalar = scalarSpring.value(at: elapsed)
                workspace.scrollingOffset = workspace.scrollingMetrics.clampedOffset(scalar)
                scheduleRefreshSession(.globalObserver("scrollingGestureSettleFrame"))
                do { try await self.dependencies.nextFrame() } catch { return }
            }
            guard let workspace, self.sessionGeneration == generation else { return }
            guard self.sessionIsCurrent(workspace) else { self.abandon(); return }
            workspace.scrollingOffset = workspace.scrollingMetrics.clampedOffset(destination)
            workspace.scrollingGestureMotionActive = false
            self.isMotionActive = false
            self.settleTask = nil
            scheduleRefreshSession(.globalObserver("scrollingGestureSettled"))
            self.clear()
            if let selected { focusSettledScrollingWindow(selected) }
            WorkspaceScrollingMinimap.shared.show(workspace)
        }
    }

    private func nearestColumn(in metrics: ScrollingWorkspaceMetrics) -> ScrollingColumnMetric? {
        nearestScrollingColumn(in: metrics, offset: workspace?.scrollingOffset ?? 0, direction: lastDirection)
    }

    private func cancelSettlement(keepOffset: Bool) {
        sessionGeneration &+= 1
        settleTask?.cancel()
        settleTask = nil
        if let workspace {
            workspace.scrollingGestureMotionActive = false
            if !keepOffset { workspace.scrollingOffset = startOffset }
        }
        isMotionActive = false
    }

    private func abandon() {
        cancelSettlement(keepOffset: true)
        clear()
        WorkspaceScrollingMinimap.shared.endGesture()
    }

    private func clear() {
        if anchor != nil { WorkspaceScrollingMinimap.shared.endGesture() }
        if let workspace, workspace.scrollingGestureSessionID != nil {
            for window in workspace.allLeafWindowsRecursive.compactMap({ $0 as? MacWindow }) {
                window.macApp.cancelFrameWrite(window.windowId)
            }
        }
        workspace?.scrollingGestureMotionActive = false
        workspace?.scrollingGestureSessionID = nil
        workspace = nil
        anchor = nil
        lastDirection = 0
        monitorWidth = 0
        monitorPoint = nil
        topology = nil
        ownerEpoch = nil
        isMotionActive = false
    }
}

/// Settling focuses the revealed column; native mode focuses the real window too.
@MainActor private func focusSettledScrollingWindow(_ window: Window) {
    guard window.focusWindow() else { return }
    if runtime.workspaceBackend.kind == .native { window.nativeFocus() }
}

/// The column whose centre is nearest the viewport's centre; ties follow the last
/// movement direction.
func nearestScrollingColumn(in metrics: ScrollingWorkspaceMetrics, offset: CGFloat, direction: CGFloat) -> ScrollingColumnMetric? {
    let center = offset + metrics.areaWidth / 2
    return metrics.columns.min { lhs, rhs in
        let a = abs(lhs.start + lhs.width / 2 - center)
        let b = abs(rhs.start + rhs.width / 2 - center)
        if abs(a - b) < 0.5, direction != 0 { return direction > 0 ? lhs.start > rhs.start : lhs.start < rhs.start }
        return a < b
    }
}
