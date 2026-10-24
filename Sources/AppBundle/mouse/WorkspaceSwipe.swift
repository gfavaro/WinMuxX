import AppKit
import Common

@MainActor
protocol WorkspaceSwipePreviewing: AnyObject {
    var isActive: Bool { get }
    var isSettling: Bool { get }
    func begin(on monitor: Monitor, target: Workspace, slidesLeft: Bool,
               isValid: @escaping @MainActor () -> Bool)
    func update(_ progress: Double, timestamp: Double)
    func settle(commit: Bool, timestamp: Double)
    func revealWorkspace()
    func cancel()
    func invalidate()
}

extension WorkspaceSwipePreview: WorkspaceSwipePreviewing {}

/// Native services stay at the application boundary; each controller owns its interaction state.
@MainActor
struct WorkspaceSwipeDependencies {
    let preview: any WorkspaceSwipePreviewing
    let monitors: () -> [Monitor]
    let pointer: () -> CGPoint
    let canNavigate: () -> Bool
    let reversed: () -> Bool
    let navigate: (@escaping @MainActor () -> Bool) async throws -> Bool
    let navigationFailed: (any Error) -> Void

    static var live: Self {
        Self(preview: WorkspaceSwipePreview.shared, monitors: { sortedMonitors }, pointer: { mouseLocation },
             canNavigate: {
                 config.workspaceSwipe.enabled && isWinMuxRuntimeReady && TrayMenuModel.shared.isEnabled &&
                     !WindowBorderController.shared.isMissionControlActive &&
                     !isMouseManipulationActive && !isLeftMouseButtonDown && !isWorkspaceSidebarDragInProgress() && !WorkspaceOverviewController.shared.isOpen
             }, reversed: { config.workspaceSwipe.reverseDirection }, navigate: { activate in
                 guard let token: RunSessionGuard = .isServerEnabled else { return false }
                 return try await runLightSession(.globalObserver("workspaceSwipe"), token, shouldSchedulePostRefresh: false, body: activate)
             }, navigationFailed: { error in
                 if TrayMenuModel.shared.isEnabled { scheduleRefreshSession(.globalObserver("workspaceSwipeInterrupted")) }
                 if !(error is CancellationError) { debugFocusLog("workspaceSwipe navigation failed: \(error)") }
             })
    }
}

@MainActor
final class WorkspaceSwipeController {
    static let shared = WorkspaceSwipeController()
    private let dependencies: WorkspaceSwipeDependencies

    init(dependencies: WorkspaceSwipeDependencies = .live) { self.dependencies = dependencies }

    private struct Gesture {
        let displayPoint: CGPoint
        let source: Workspace
        let target: Workspace
    }
    private var recognizer = WorkspaceTouchRecognizer()
    private var gesture: Gesture?
    private(set) var pending: Task<Void, Never>?
    private var generation = 0

    func reset() {
        cancelVisualInteraction()
        dependencies.preview.invalidate()
        recognizer = WorkspaceTouchRecognizer()
        recognizer.cancel()
        generation += 1
        pending?.cancel()
        pending = nil
    }

    func cancelVisualInteraction() {
        guard gesture != nil || dependencies.preview.isActive else { return }
        gesture = nil
        recognizer.cancel()
        dependencies.preview.cancel()
    }

    private var canNavigate: Bool { dependencies.canNavigate() }

    func handle(_ frame: WorkspaceTouchFrame) {
        guard canNavigate else {
            cancelVisualInteraction()
            recognizer.cancel()
            if frame.fingers == 0 { _ = recognizer.receive(frame, displayPoint: nil, reversed: false) }
            return
        }
        let point = dependencies.pointer()
        let display = dependencies.monitors().first { $0.rect.contains(point) }?.rect.topLeftCorner
        guard let event = recognizer.receive(frame, displayPoint: display, reversed: dependencies.reversed()) else { return }
        switch event {
            case .began(let request):
                guard pending == nil, !dependencies.preview.isSettling,
                      let monitor = dependencies.monitors().first(where: { $0.rect.topLeftCorner == request.displayPoint }),
                      let target = workspaceSwipeTarget(on: monitor, isNext: request.isNext) else {
                    recognizer.cancel()
                    return
                }
                gesture = Gesture(displayPoint: request.displayPoint, source: monitor.activeWorkspace, target: target)
                dependencies.preview.begin(on: monitor, target: target, slidesLeft: request.slidesLeft) { [weak self] in
                    guard let self, let gesture = self.gesture,
                          monitor.activeWorkspace === gesture.source else { return false }
                    return self.gestureIsValid(gesture, on: monitor)
                }
                dependencies.preview.update(request.progress, timestamp: frame.timestamp)
            case .changed(let progress):
                guard let gesture, let monitor = dependencies.monitors().first(where: { $0.rect.topLeftCorner == gesture.displayPoint }),
                      monitor.activeWorkspace === gesture.source else { cancelVisualInteraction(); return }
                dependencies.preview.update(progress, timestamp: frame.timestamp)
                WorkspaceMotionDiagnostics.record("Horizontal callback to preview update", milliseconds: (CACurrentMediaTime() - frame.receivedAt) * 1000)
            case .ended(let commit):
                finish(commit: commit, timestamp: frame.timestamp)
            case .cancelled:
                finish(commit: false, timestamp: frame.timestamp)
        }
    }

    private func finish(commit: Bool, timestamp: Double) {
        guard let gesture else { return }
        self.gesture = nil
        guard commit else { dependencies.preview.settle(commit: false, timestamp: timestamp); return }
        guard let monitor = dependencies.monitors().first(where: { $0.rect.topLeftCorner == gesture.displayPoint }),
              monitor.activeWorkspace === gesture.source, gestureIsValid(gesture, on: monitor) else {
            dependencies.preview.settle(commit: false, timestamp: timestamp)
            return
        }
        dependencies.preview.settle(commit: true, timestamp: timestamp)
        let released = CACurrentMediaTime()
        let currentGeneration = generation
        pending = Task { @MainActor in
            defer { if generation == currentGeneration { pending = nil } }
            guard generation == currentGeneration else { return }
            guard !Task.isCancelled, canNavigate else {
                dependencies.preview.cancel()
                return
            }
            do {
                let activated = try await dependencies.navigate { [self] in
                    guard !Task.isCancelled, self.generation == currentGeneration, self.canNavigate,
                          let monitor = dependencies.monitors().first(where: { $0.rect.topLeftCorner == gesture.displayPoint }),
                          monitor.activeWorkspace === gesture.source, self.gestureIsValid(gesture, on: monitor) else { return false }
                    resetClosedWindowsCache()
                    return activateWorkspaceForUser(gesture.target, on: monitor)
                }
                guard generation == currentGeneration else { return }
                if activated, monitor.activeWorkspace === gesture.target {
                    WorkspaceMotionDiagnostics.record("Swipe release to layout ready", milliseconds: (CACurrentMediaTime() - released) * 1000)
                    dependencies.preview.revealWorkspace()
                } else { dependencies.preview.cancel() }
            } catch {
                guard generation == currentGeneration else { return }
                dependencies.preview.cancel()
                dependencies.navigationFailed(error)
            }
        }
    }

    private func gestureIsValid(_ gesture: Gesture, on monitor: Monitor) -> Bool {
        Workspace.existing(byName: gesture.target.name) === gesture.target &&
            !gesture.target.isArchived && gesture.target.projectId == gesture.source.projectId &&
            workspaceMonitorForUserActivation(gesture.target, on: monitor).rect.topLeftCorner == monitor.rect.topLeftCorner
    }
}

@MainActor
@discardableResult
func navigateWorkspaceBySwipe(on monitor: Monitor, isNext: Bool) -> Bool {
    guard let target = workspaceSwipeTarget(on: monitor, isNext: isNext) else { return false }
    resetClosedWindowsCache()
    return activateWorkspaceForUser(target, on: monitor)
}

@MainActor
func workspaceSwipeTarget(on monitor: Monitor, isNext: Bool) -> Workspace? {
    getNextPrevWorkspace(current: monitor.activeWorkspace, isNext: isNext, wrapAround: false,
                        stdin: nil, on: monitor)
}
