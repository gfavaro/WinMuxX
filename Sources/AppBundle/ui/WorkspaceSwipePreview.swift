import AppKit
import Common
import QuartzCore

struct WorkspaceSwipePreviewGeometry {
    /// Navigation progress and visible travel share the same scale.
    static func trackingProgress(_ progress: Double) -> Double {
        progress.isFinite ? min(1, max(0, progress)) : 0
    }

    static func settlingAnimation(from: CGFloat, to: CGFloat, speed: CGFloat, duration: Double) -> CASpringAnimation {
        WorkspaceGestureAnimation.settlingAnimation(keyPath: "transform.translation.x", from: from, to: to, speed: speed, duration: duration)
    }

    static func offsets(width: CGFloat, progress: Double, slidesLeft: Bool) -> (outgoing: CGFloat, incoming: CGFloat) {
        let travel = width * CGFloat(min(1, max(0, progress)))
        let outgoing = slidesLeft ? -travel : travel
        return (outgoing, outgoing + (slidesLeft ? width : -width))
    }
}

/// Snapshot-only interaction. Real windows stay on their workspace until release.
@MainActor
final class WorkspaceSwipePreview {
    static let shared = WorkspaceSwipePreview()
    private let snapshots: WorkspaceSwipeSnapshots
    init(snapshots: WorkspaceSwipeSnapshots = WorkspaceSwipeSnapshots()) { self.snapshots = snapshots }
    struct Timing {
        let generation: Int
        let cacheHit: Bool
        var captureMs: Double?
        var captureReadyMs: Double?
        var requestMs: Double
        var panelMs: Double?
        var mainMs: Double
        var submissionMs: Double?
        var workerMs: Double?
    }
    static let timingSampleLimit = 128
    private(set) var timings: [Timing] = []
    private(set) var surfaceCreations = 0
    private var panel: NSPanel?
    private var outgoing: CALayer?
    private var incoming: CALayer?
    private var slidesLeft = true
    private var progress = 0.0
    private var sampleTime = 0.0
    private var velocity = 0.0
    private var generation = 0
    private var completion: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var phase = WorkspaceSwipePreviewPhase.idle
    /// The screen grabbed as a swipe starts, before its direction is known, so the preview
    /// can appear with the first movement instead of one capture later.
    private struct TouchdownFront {
        let key: WorkspaceSwipeSnapshotKey
        let at: Double
        var image: CGImage?
        var arrived: ((CGImage) -> Void)?
    }
    private var touchdownFront: TouchdownFront?
    var hasTouchdownFront: Bool { touchdownFront?.image != nil }
    private var slideEndedAt: Double?
    static let touchdownFrontLifetime = 1.0
    var isSettling: Bool { phase.isSettling }
    var isActive: Bool { phase != .idle }

    private var canPreview: Bool {
        !isUnitTest && config.animations.enabled && config.workspaceSwipe.animationDurationMs > 0 &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion &&
            !WindowBorderController.shared.isMissionControlActive && CGPreflightScreenCaptureAccess()
    }

    private func area(on monitor: Monitor) -> (rect: Rect, capture: WorkspaceSwipeSnapshotRequest) {
        let visible = monitor.visibleRect
        let inset = monitor.workspaceSidebarInset
        let rect = Rect(topLeftX: visible.minX + (config.workspaceSidebar.position == .left ? inset : 0),
                        topLeftY: visible.minY, width: visible.width - inset, height: visible.height)
        let sourceKey = WorkspaceSwipeSnapshotKey(workspace: monitor.activeWorkspace, monitor: monitor, rect: rect)
        let captureRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        return (rect, WorkspaceSwipeSnapshotRequest(screenKey: sourceKey, rect: captureRect))
    }

    /// A swipe has started on the monitor; its direction is not known yet.
    func prepareFront(on monitor: Monitor) {
        guard phase == .idle, canPreview else { return }
        prepareFront(area(on: monitor).capture)
    }

    func prepareFront(_ capture: WorkspaceSwipeSnapshotRequest) {
        guard phase == .idle else { return }
        let key = capture.key
        touchdownFront = TouchdownFront(key: key, at: CACurrentMediaTime())
        snapshots.request(capture) { [weak self] result in
            guard let self, self.touchdownFront?.key == key, self.touchdownFront?.image == nil else { return }
            guard case .success(let front) = result else { self.touchdownFront = nil; return }
            if let arrived = self.touchdownFront?.arrived {
                self.touchdownFront = nil
                arrived(front.image)
            } else {
                self.touchdownFront?.image = front.image
            }
        }
    }

    func begin(on monitor: Monitor, target: Workspace, slidesLeft: Bool,
               isValid: @escaping @MainActor () -> Bool) {
        guard canPreview else {
            invalidate()
            return
        }
        let started = CACurrentMediaTime()
        let (rect, capture) = area(on: monitor)
        let request = WorkspaceSwipeSnapshotRequest(workspace: target, monitor: monitor, rect: rect)
        begin(request: request, capture: capture, rect: rect, slidesLeft: slidesLeft, started: started) {
            isValid() && CGPreflightScreenCaptureAccess()
        }
    }

    /// Screen capture uses the same bounded worker as incoming composition. Only the
    /// newest interaction can publish; lifting before capture finishes cancels the preview.
    func begin(request: WorkspaceSwipeSnapshotRequest, capture: WorkspaceSwipeSnapshotRequest,
               rect: Rect, slidesLeft: Bool, started: Double = CACurrentMediaTime(),
               isValid: @escaping @MainActor () -> Bool = { true }) {
        if var front = touchdownFront, front.key == capture.key, CACurrentMediaTime() - front.at < Self.touchdownFrontLifetime {
            if let image = front.image {
                touchdownFront = nil
                return begin(request: request, front: image, rect: rect, slidesLeft: slidesLeft, started: started, isValid: isValid)
            }
            // Still capturing: take that capture over rather than starting the same one again.
            clear()
            let cached = snapshots.cache.image(for: request.key)
            prepare(slidesLeft: slidesLeft, cacheHit: cached != nil, captureMs: nil,
                    requestMs: (CACurrentMediaTime() - started) * 1000)
            let token = generation
            front.arrived = { [weak self] image in
                guard let self, self.generation == token, self.phase == .preparing else { return }
                guard isValid() else { self.invalidate(); return }
                self.updateTiming { $0.captureReadyMs = (CACurrentMediaTime() - started) * 1000 }
                self.prepareIncoming(request, front: image, cached: cached, rect: rect, started: started, isValid: isValid)
            }
            touchdownFront = front
            return
        }
        cancel()
        let cached = snapshots.cache.image(for: request.key)
        prepare(slidesLeft: slidesLeft, cacheHit: cached != nil, captureMs: nil,
                requestMs: (CACurrentMediaTime() - started) * 1000)
        let token = generation
        snapshots.request(capture) { [weak self] result in
            guard let self, self.generation == token, self.phase == .preparing else { return }
            guard isValid() else { self.invalidate(); return }
            switch result {
                case .success(let front):
                    self.updateTiming {
                        $0.captureMs = front.renderMs
                        $0.captureReadyMs = (CACurrentMediaTime() - started) * 1000
                    }
                    self.prepareIncoming(request, front: front.image, cached: cached, rect: rect,
                                         started: started, isValid: isValid)
                case .failure: self.cancel()
            }
        }
        updateTiming { $0.mainMs = (CACurrentMediaTime() - started) * 1000 }
    }

    /// Synthetic front images exercise the same presentation path without desktop capture.
    func begin(request: WorkspaceSwipeSnapshotRequest, front: CGImage, rect: Rect, slidesLeft: Bool,
               started: Double = CACurrentMediaTime(),
               isValid: @escaping @MainActor () -> Bool = { true }) {
        cancel()
        let cached = snapshots.cache.image(for: request.key)
        prepare(slidesLeft: slidesLeft, cacheHit: cached != nil, captureMs: 0, requestMs: 0)
        prepareIncoming(request, front: front, cached: cached, rect: rect, started: started, isValid: isValid)
        updateTiming { $0.mainMs = (CACurrentMediaTime() - started) * 1000 }
    }

    private func prepare(slidesLeft: Bool, cacheHit: Bool, captureMs: Double?, requestMs: Double) {
        self.slidesLeft = slidesLeft
        phase = .preparing
        timings.append(Timing(generation: generation, cacheHit: cacheHit, captureMs: captureMs,
                              requestMs: requestMs, mainMs: 0))
        if timings.count > Self.timingSampleLimit { timings.removeFirst() }
        let token = generation
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard let self, self.generation == token else { return }
            WorkspaceSwipeController.shared.cancelVisualInteraction()
        }
    }

    private func prepareIncoming(_ request: WorkspaceSwipeSnapshotRequest, front: CGImage, cached: CGImage?,
                                 rect: Rect, started: Double, isValid: @escaping @MainActor () -> Bool) {
        if let cached {
            phase.imageReady()
            show(front: front, back: cached, rect: rect, started: started)
        }
        let token = generation
        snapshots.request(request) { [weak self] result in
            guard let self, self.generation == token,
                  self.phase == .preparing || self.phase == .tracking else { return }
            guard isValid() else { self.invalidate(); return }
            switch result {
                case .success(let snapshot):
                    self.updateTiming { $0.workerMs = snapshot.renderMs }
                    if self.phase == .preparing {
                        self.phase.imageReady()
                        self.show(front: front, back: snapshot.image, rect: rect, started: started)
                    } else {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        self.incoming?.contents = snapshot.image
                        CATransaction.commit()
                    }
                case .failure:
                    if self.phase == .preparing { self.cancel() }
            }
        }
    }

    private func updateTiming(_ update: (inout Timing) -> Void) {
        guard let index = timings.lastIndex(where: { $0.generation == generation }) else { return }
        update(&timings[index])
    }

    private func makeSurface(rect: Rect) -> NSPanel {
        surfaceCreations += 1
        let panel = NSPanel(contentRect: rect.toAppKitScreenRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        let root = CALayer()
        root.masksToBounds = true
        view.layer = root
        let outgoing = CALayer(), incoming = CALayer()
        for layer in [outgoing, incoming] {
            layer.contentsGravity = .resize
            root.addSublayer(layer)
        }
        panel.contentView = view
        self.panel = panel
        self.outgoing = outgoing
        self.incoming = incoming
        return panel
    }

    private func show(front: CGImage, back: CGImage, rect: Rect, started: Double) {
        let panelStarted = CACurrentMediaTime()
        let panel = self.panel ?? makeSurface(rect: rect)
        let frame = rect.toAppKitScreenRect
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let view = panel.contentView {
            view.layer?.frame = view.bounds
            outgoing?.frame = view.bounds
            incoming?.frame = view.bounds
        }
        outgoing?.contents = front
        incoming?.contents = back
        CATransaction.commit()
        applyProgress()
        panel.orderFrontRegardless()
        updateTiming {
            $0.panelMs = (CACurrentMediaTime() - panelStarted) * 1000
            $0.submissionMs = (CACurrentMediaTime() - started) * 1000
        }
    }

    func update(_ progress: Double, timestamp: Double = CACurrentMediaTime()) {
        guard phase == .tracking || phase == .preparing else { return }
        let now = timestamp
        guard now.isFinite else { return }
        let next = WorkspaceSwipePreviewGeometry.trackingProgress(progress)
        let dt = now - sampleTime
        velocity = dt > 0.001 && dt < 0.1 ? (next - self.progress) / dt : 0
        sampleTime = now
        self.progress = next
        if phase == .tracking {
            applyProgress()
        }
    }

    private func applyProgress() {
        guard let panel else { return }
        let offset = WorkspaceSwipePreviewGeometry.offsets(width: panel.frame.width, progress: progress, slidesLeft: slidesLeft)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, to) in [(outgoing, offset.outgoing), (incoming, offset.incoming)] {
            guard let layer else { continue }
            layer.transform = CATransform3DMakeTranslation(to, 0, 0)
        }
        CATransaction.commit()
    }

    func settle(commit: Bool, timestamp: Double = CACurrentMediaTime()) {
        snapshots.cancel()
        if phase == .preparing { cancel(); return }
        guard let panel, phase == .tracking else { return }
        phase.settle(commit: commit)
        let start = WorkspaceSwipePreviewGeometry.offsets(width: panel.frame.width, progress: progress, slidesLeft: slidesLeft)
        let releaseVelocity = timestamp >= sampleTime && timestamp - sampleTime < 0.08 ? velocity : 0
        let end = WorkspaceSwipePreviewGeometry.offsets(width: panel.frame.width, progress: commit ? 1 : 0, slidesLeft: slidesLeft)
        let remaining = commit ? 1 - progress : progress
        let duration = max(0.12, Double(config.workspaceSwipe.animationDurationMs) / 1000 * sqrt(remaining))
        var settlingDuration = 0.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, from, to) in [(outgoing, start.outgoing, end.outgoing), (incoming, start.incoming, end.incoming)] {
            guard let layer else { continue }
            let visible = layer.presentation()?.transform.m41 ?? from
            layer.transform = CATransform3DMakeTranslation(to, 0, 0)
            let speed = releaseVelocity * panel.frame.width * (slidesLeft ? -1 : 1)
            let animation = WorkspaceSwipePreviewGeometry.settlingAnimation(from: visible, to: to, speed: speed, duration: duration)
            let spring = WorkspaceGestureScalarSpring(from: visible, to: to, animation: animation)
            settlingDuration = max(settlingDuration, spring.visibleDuration(within: 1, limit: animation.duration))
            layer.add(animation, forKey: "workspaceSwipe")
        }
        CATransaction.commit()
        let token = generation
        completion = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(settlingDuration)) } catch { return }
            guard let self, self.generation == token else { return }
            self.phase.animationFinished()
            if self.phase == .waitingForWorkspace { self.slideEndedAt = CACurrentMediaTime() }
            self.finishIfReady()
        }
    }

    func revealWorkspace() {
        // How long the finished slide stood still waiting for the real workspace.
        if phase == .waitingForWorkspace || phase == .waitingForAnimationAndWorkspace {
            WorkspaceMotionDiagnostics.record("Swipe landing wait after slide",
                milliseconds: slideEndedAt.map { (CACurrentMediaTime() - $0) * 1000 } ?? 0)
        }
        phase.workspaceReady()
        finishIfReady()
    }

    /// Real windows take over from the snapshots with a short fade rather than in one frame,
    /// so whatever changed since the snapshots were taken does not flash.
    private func finishIfReady() {
        guard phase == .idle else { return }
        guard let panel, panel.isVisible else { return cancel() }
        let token = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.handOffDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.cancel()
            }
        })
    }
    static let handOffDuration = 0.08

    func invalidate() {
        cancel()
        snapshots.invalidate()
        panel?.contentView = nil
        panel?.close()
        panel = nil
        outgoing = nil
        incoming = nil
    }

    isolated deinit { panel?.close() }

    func cancel() {
        snapshots.cancel()
        touchdownFront = nil
        clear()
    }

    /// Ends the presentation; a capture still running for the next swipe is left alone.
    private func clear() {
        slideEndedAt = nil
        generation += 1
        completion?.cancel(); completion = nil
        deadline?.cancel(); deadline = nil
        panel?.orderOut(nil)
        if let panel {
            // Replaces a hand-off fade still running, which would otherwise hide the next preview.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
            }
        }
        // A reusable surface must never retain a previous workspace's pixels or animations.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [outgoing, incoming] {
            layer?.removeAllAnimations()
            layer?.contents = nil
            layer?.transform = CATransform3DIdentity
        }
        CATransaction.commit()
        progress = 0
        sampleTime = 0
        velocity = 0
        phase = .idle
    }

}
