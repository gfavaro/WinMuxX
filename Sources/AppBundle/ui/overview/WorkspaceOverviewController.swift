import AppKit
import Common

struct WorkspaceOverviewDisplay {
    let id: MonitorViewportId
    let name: String
    let frame: CGRect
    var activeWorkspace: WorkspaceId? = nil
}

@MainActor
protocol WorkspaceOverviewPresenting: AnyObject {
    func present(key: Bool)
    func dismissOverview()
    func dismissOverview(animated: Bool, completion: @escaping @MainActor () -> Void)
    func present(key: Bool, gestureProgress: Double?)
    func updateGesture(progress: Double)
    func settleGesture(velocity: Double)
    func dismissOverview(animated: Bool, velocity: Double, completion: @escaping @MainActor () -> Void)
}

extension WorkspaceOverviewPresenting {
    func present(key: Bool, gestureProgress: Double?) { present(key: key) }
    func updateGesture(progress: Double) {}
    func settleGesture(velocity: Double) {}
    func dismissOverview(animated: Bool, velocity: Double, completion: @escaping @MainActor () -> Void) {
        dismissOverview(animated: animated, completion: completion)
    }
    func dismissOverview(animated: Bool, completion: @escaping @MainActor () -> Void) {
        dismissOverview()
        completion()
    }
}

@MainActor
struct WorkspaceOverviewDependencies {
    var project: () -> WorkspaceProjectId
    var displays: () -> [WorkspaceOverviewDisplay]
    var cards: (WorkspaceProjectId) -> [WorkspaceOverviewCard]
    var canShow: () -> Bool
    var ranks: @Sendable (UUID) async -> [UInt32: Int]
    var render: @Sendable (WorkspaceSwipeSnapshotRequest) async throws -> CGImage
    var makePanel: (WorkspaceOverviewDisplayModel, WorkspaceOverviewDisplay) -> any WorkspaceOverviewPresenting
    var activate: (WorkspaceOverviewCard, WorkspaceOverviewWindow?) async -> Bool
    var releaseCaptureSession: @Sendable (UUID) async -> Void = { _ in }
    var nativeIntegration = false

    static var live: Self {
        Self(project: { focus.workspace.projectId }, displays: {
            sortedMonitors.map { monitor in
                WorkspaceOverviewDisplay(id: MonitorViewportId(monitor), name: monitor.name,
                    frame: CGRect(x: monitor.rect.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - monitor.rect.maxY,
                                  width: monitor.width, height: monitor.height), activeWorkspace: monitor.activeWorkspace.id)
            }
        }, cards: { buildWorkspaceOverviewCards(project: $0, monitors: sortedMonitors) }, canShow: {
            isWinMuxRuntimeReady && TrayMenuModel.shared.isEnabled &&
                !WindowBorderController.shared.isMissionControlActive && !isMouseManipulationActive &&
                !isLeftMouseButtonDown && !isWorkspaceSidebarDragInProgress()
        }, ranks: { await WorkspaceSwipeSnapshotRenderer.shared.prepareOverview($0) }, render: { request in
            try await WorkspaceSwipeSnapshotRenderer.shared.renderOverview(request)
        }, makePanel: { model, display in
            WorkspaceOverviewPanel(model: model, monitorName: display.name, frame: display.frame)
        }, activate: { card, selection in
            guard let token: RunSessionGuard = .isServerEnabled else { return false }
            do {
                return try await runLightSession(.globalObserver("workspaceOverviewSelection"), token, shouldSchedulePostRefresh: false) {
                    guard let workspace = Workspace.existing(byName: card.name), workspace.id == card.id,
                          workspace.projectId == focus.workspace.projectId,
                          MonitorViewportId(workspace.workspaceMonitor) == card.monitor,
                          let monitor = sortedMonitors.first(where: { MonitorViewportId($0) == card.monitor }) else { return false }
                    if let selection {
                        guard let window = Window.get(byId: selection.id), ObjectIdentifier(window) == selection.identity,
                              window.app.pid == selection.pid, window.nodeWorkspace === workspace,
                              workspaceOverviewIncludesWindow(window) else { return false }
                        let observation = window.nativeStateObservationToken()
                        guard let native = try await window.readNativeState(), !native.fullscreen, !native.minimized,
                              observation == window.nativeStateObservationToken(),
                              Window.get(byId: selection.id) === window, window.nodeWorkspace === workspace, workspaceOverviewIncludesWindow(window),
                              Workspace.existing(byName: card.name) === workspace, workspace.projectId == focus.workspace.projectId,
                              TrayMenuModel.shared.isEnabled,
                              MonitorViewportId(workspace.workspaceMonitor) == card.monitor,
                              activateWorkspaceForUser(workspace, on: monitor) else { return false }
                        _ = window.focusWindow()
                        window.nativeFocus()
                        return true
                    }
                    return activateWorkspaceForUser(workspace, on: monitor)
                }
            } catch { return false }
        }, releaseCaptureSession: { await WorkspaceSwipeSnapshotRenderer.shared.endOverview($0) }, nativeIntegration: true)
    }
}

@MainActor
final class WorkspaceOverviewController {
    static let shared = WorkspaceOverviewController(dependencies: .live)
    enum Phase { case closed, opening, open, closing }
    private(set) var phase: Phase = .closed
    var isOpen: Bool { phase == .opening || phase == .open }
    let dependencies: WorkspaceOverviewDependencies
    private(set) var models: [WorkspaceOverviewDisplayModel] = []
    private(set) var panels: [any WorkspaceOverviewPresenting] = []
    private var reusablePanels: [MonitorViewportId: WorkspaceOverviewPanel] = [:]
    private var project: WorkspaceProjectId?
    private var generation = 0
    private var captureSession = UUID()
    private(set) var task: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var attempted = Set<WorkspaceId>()
    private var invalidated = Set<WorkspaceId>()
    private var ranks: [UInt32: Int] = [:]
    private var ranksGeneration: Int?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var previousApp: NSRunningApplication?
    var gestureOpening: Bool?
    static let imageBudget = 32 * 1024 * 1024
    var retainedImageBytes: Int {
        models.reduce(0) { $0 + $1.images.values.reduce(0) { $0 + $1.bytesPerRow * $1.height } }
    }

    init(dependencies: WorkspaceOverviewDependencies) { self.dependencies = dependencies }

    @discardableResult func show(gestureProgress: Double? = nil) -> Bool {
        if phase == .closing { finishDismiss() }
        if isOpen { return true }
        guard dependencies.canShow(), selectionTask == nil else { return false }
        let setupStarted = CACurrentMediaTime()
        let displays = dependencies.displays()
        let connected = Set(displays.map(\.id))
        for id in Array(reusablePanels.keys) where !connected.contains(id) {
            reusablePanels.removeValue(forKey: id)?.dismissOverview()
        }
        guard !displays.isEmpty else { return false }
        generation += 1; captureSession = UUID(); phase = .opening
        runtime.publicState.overviewVisible = true
        requestPublicStateUpdate()
        project = dependencies.project()
        attempted.removeAll(); invalidated.removeAll(); ranks.removeAll()
        if dependencies.nativeIntegration {
            WorkspaceSidebarPanel.refreshAll()
            GlobalObserver.cancelFocusFollowsMouse()
            WorkspaceSwipeController.shared.cancelVisualInteraction()
            SwitcherPalettePanel.shared.dismiss()
            previousApp = NSWorkspace.shared.frontmostApplication
            if previousApp?.processIdentifier == myPid { previousApp = (focus.windowOrNil?.app as? MacApp)?.nsApp }
        }
        let cards = dependencies.cards(project!)
        for display in displays {
            let reused = reusablePanels.removeValue(forKey: display.id)
            reused?.prepareForReuse(name: display.name, frame: display.frame)
            let model = reused?.model ?? WorkspaceOverviewDisplayModel()
            model.monitor = display.id
            model.cards = cards.filter { $0.monitor == display.id }
            if let current = model.cards.firstIndex(where: { $0.id == display.activeWorkspace }) {
                model.selection = current; model.page = current / WorkspaceOverviewDisplayModel.pageSize
            }
            model.activate = { [weak self] id, window in self?.select(id, window: window) }
            model.pageChanged = { [weak self] in self?.pagesChanged() }
            model.dismiss = { [weak self] in self?.dismiss() }
            models.append(model)
            panels.append(reused ?? dependencies.makePanel(model, display))
        }
        for (index, panel) in panels.enumerated() {
            let key = dependencies.nativeIntegration ? displays[index].id == MonitorViewportId(focus.workspace.workspaceMonitor) : index == 0
            panel.present(key: key, gestureProgress: gestureProgress)
        }
        WorkspaceMotionDiagnostics.record("Overview setup to panel submission", milliseconds: (CACurrentMediaTime() - setupStarted) * 1000)
        phase = .open
        if dependencies.nativeIntegration {
            installObservers()
            WorkspaceGestureCoordinator.shared.overviewPresentationChanged()
        }
        startCaptures()
        return true
    }

    func dismiss(animated: Bool = true, restoreFocus: Bool = true, gestureVelocity: Double = 0) {
        gestureOpening = nil
        guard phase != .closed else { return }
        if phase == .closing {
            if !animated { finishDismiss() }
            return
        }
        phase = .closing; generation += 1
        runtime.publicState.overviewVisible = false
        requestPublicStateUpdate()
        let closingGeneration = generation
        task?.cancel()
        let release = dependencies.releaseCaptureSession, session = captureSession
        Task(priority: .utility) { await release(session) }
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        for model in models {
            model.activate = nil; model.pageChanged = nil; model.dismiss = nil
        }
        attempted.removeAll(); invalidated.removeAll(); ranks.removeAll(); project = nil
        if dependencies.nativeIntegration {
            WorkspaceGestureCoordinator.shared.overviewPresentationChanged()
            WorkspaceSidebarPanel.refreshAll()
        }
        if restoreFocus, dependencies.nativeIntegration, NSWorkspace.shared.frontmostApplication?.processIdentifier == myPid {
            previousApp?.activate(options: [])
        }
        previousApp = nil
        var remaining = panels.count
        if remaining == 0 { finishDismiss(); return }
        for panel in panels {
            panel.dismissOverview(animated: animated, velocity: gestureVelocity) { [weak self] in
                guard let self, self.phase == .closing, self.generation == closingGeneration else { return }
                remaining -= 1
                if remaining == 0 { self.finishDismiss() }
            }
        }
    }

    /// At most one retiring presentation exists. Reopening tears it down before
    /// retaining a new image budget; stale animation completions cannot close it.
    private func finishDismiss() {
        guard phase == .closing else { return }
        phase = .closed
        let retiredPanels = panels, retiredModels = models
        panels.removeAll(); models.removeAll()
        for (panel, model) in zip(retiredPanels, retiredModels) {
            if let native = panel as? WorkspaceOverviewPanel, let id = model.monitor {
                native.hideForReuse()
                reusablePanels[id]?.dismissOverview()
                reusablePanels[id] = native
            } else { panel.dismissOverview() }
            model.images.removeAll(); model.cards.removeAll()
            model.page = 0; model.selection = 0; model.selectedWindow = nil
            model.activate = nil; model.pageChanged = nil; model.dismiss = nil
        }
    }

    /// Runtime and display invalidation release cached native surfaces as well as sessions.
    func invalidate() {
        dismiss(animated: false)
        for panel in reusablePanels.values { panel.dismissOverview() }
        reusablePanels.removeAll()
    }

    /// Called by the established refresh path and application notifications; no polling.
    func modelDidChange() {
        guard isOpen, let project else { return }
        guard dependencies.canShow(), dependencies.project() == project else { dismiss(restoreFocus: false); return }
        let cards = ordered(dependencies.cards(project))
        for model in models {
            let monitor = model.monitor
            guard let monitor else { continue }
            let next = cards.filter { $0.monitor == monitor }
            guard next != model.cards else { continue }
            let selectedCard = model.selectedCard
            let selectedWindow = selectedCard?.windows.first { $0.id == model.selectedWindow }
            let previous = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0) })
            for card in next where previous[card.id] != card { invalidated.insert(card.id); model.images[card.id] = nil }
            let ids = Set(next.map(\.id))
            model.images = model.images.filter { ids.contains($0.key) }
            model.cards = next
            model.selection = next.firstIndex { $0.id == selectedCard?.id } ?? min(model.selection, max(0, next.count - 1))
            model.page = model.selection / WorkspaceOverviewDisplayModel.pageSize
            if !((model.selectedCard?.windows.contains { $0.id == selectedWindow?.id && $0.identity == selectedWindow?.identity }) ?? false) {
                model.selectedWindow = nil
            }
        }
    }

    func nativeWindowChanged(_ id: UInt32) {
        guard isOpen else { return }
        for model in models {
            for card in model.cards where card.windows.contains(where: { $0.id == id }) {
                invalidated.insert(card.id); model.images[card.id] = nil
            }
        }
    }

    private func pagesChanged() {
        for model in models {
            let visible = Set(model.visibleCards.map(\.id))
            model.images = model.images.filter { visible.contains($0.key) }
        }
        startCaptures()
    }
    private func ordered(_ cards: [WorkspaceOverviewCard]) -> [WorkspaceOverviewCard] {
        cards.map { card in
            var result = card
            result.windows = card.windows.enumerated().sorted {
                let a = ranks[$0.element.id] ?? Int.max, b = ranks[$1.element.id] ?? Int.max
                return a == b ? $0.offset < $1.offset : a > b
            }.map(\.element)
            return result
        }
    }

    private func nextCapture() -> (Int, WorkspaceOverviewCard, WorkspaceSwipeSnapshotRequest)? {
        guard isOpen else { return nil }
        let candidates = models.compactMap(\.selectedCard) + models.flatMap(\.visibleCards)
        for card in candidates where !attempted.contains(card.id) && !invalidated.contains(card.id) {
                attempted.insert(card.id)
                let key = WorkspaceSwipeSnapshotKey(workspace: card.id, display: card.monitor.description,
                    rect: CGRect(origin: .zero, size: card.desktopSize))
                let windows = card.windows.compactMap { window -> WorkspaceSwipeSnapshotRequest.Window? in
                    guard let rect = window.frame else { return nil }
                    return .init(id: window.id, frame: CGRect(x: rect.minX * card.desktopSize.width,
                        y: (1 - rect.maxY) * card.desktopSize.height,
                        width: rect.width * card.desktopSize.width, height: rect.height * card.desktopSize.height))
                }
                var request = WorkspaceSwipeSnapshotRequest(key: key, windows: windows)
                request.overviewSession = captureSession
                request.maximumPixelSize = CGSize(width: 640, height: 360)
                request.windowsAreBackToFront = true
                request.allowCapture = !dependencies.nativeIntegration || CGPreflightScreenCaptureAccess()
                guard !windows.isEmpty else { continue }
                return (generation, card, request)
        }
        return nil
    }

    private func startCaptures() {
        // Keep the slot until native work actually returns, including after cancellation.
        guard isOpen, task == nil else { return }
        let ranks = dependencies.ranks, render = dependencies.render, session = captureSession
        task = Task(priority: .utility) { @MainActor [weak self] in
            let generation = self?.generation
            let ordering = self?.ranksGeneration == generation ? (self?.ranks ?? [:]) : await ranks(session)
            if let self, self.isOpen, self.generation == generation {
                self.ranks = ordering
                self.ranksGeneration = self.generation
                for model in self.models { model.cards = self.ordered(model.cards) }
            }
            while !Task.isCancelled, let (generation, card, request) = self?.nextCapture() {
                let image = try? await render(request)
                self?.accept(image, card: card, generation: generation)
            }
            if let self {
                self.task = nil
                // A new opening may have replaced a cancelled session while native work finished.
                if self.isOpen && self.generation != generation { self.startCaptures() }
            }
        }
    }
    private func accept(_ image: CGImage?, card: WorkspaceOverviewCard, generation: Int) {
        guard isOpen, self.generation == generation, !invalidated.contains(card.id), let image,
              image.width <= 640, image.height <= 360,
              retainedImageBytes + image.bytesPerRow * image.height <= Self.imageBudget,
              let model = models.first(where: { $0.visibleCards.contains(card) }) else { return }
        model.images[card.id] = image
    }

    private func select(_ id: WorkspaceId, window: UInt32?) {
        guard selectionTask == nil, let card = models.flatMap(\.cards).first(where: { $0.id == id }) else { return }
        let selection = window.flatMap { id in card.windows.first { $0.id == id } }
        if window != nil && selection == nil { return }
        let activate = dependencies.activate
        dismiss(restoreFocus: false)
        selectionTask = Task { @MainActor [weak self] in
            _ = await activate(card, selection)
            self?.selectionTask = nil
        }
    }

    private func installObservers() {
        func observe(_ center: NotificationCenter, _ name: Notification.Name, dismiss: Bool) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if dismiss { self?.dismiss(restoreFocus: false) } else { self?.modelDidChange() }
                }
            }
            observers.append((center, token))
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification, dismiss: true)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.activeSpaceDidChangeNotification] { observe(workspace, name, dismiss: true) }
        let activation = workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid, pid != myPid { self?.dismiss(restoreFocus: false) }
            }
        }
        observers.append((workspace, activation))
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] { observe(workspace, name, dismiss: false) }
    }
}
