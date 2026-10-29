import AppKit
import Combine
import Common

@MainActor
final class WorkspacePresentationController {
    static let shared = WorkspacePresentationController()

    enum EndReason { case explicit, invalidated }

    private struct Session {
        let epoch: UInt64
        let window: MacWindow
        let windowId: UInt32
        let pid: Int32
        let launchDate: Date?
        let bundleId: String?
        let workspace: Workspace
        let workspaceId: WorkspaceId
        let projectId: WorkspaceProjectId
        let viewportId: MonitorViewportId
        let displayUUID: String?
        let originalFrame: Rect
        let originalLastAppliedFrame: Rect?
        let scrollingOffset: CGFloat
        let scrollingAnchorWindowId: UInt32?
        let scrollingAnchorViewportPosition: CGFloat?
        let scrollingAnchorAreaWidth: CGFloat?
        let scrollingFocusWindowId: UInt32?
        let tiled: Bool
    }

    private let backdrop = PresentationBackdropPanel()
    private var session: Session?
    private var pendingFloatingRestores: [UInt32: Session] = [:]
    private var nextEpoch: UInt64 = 0
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var trayObservation: AnyCancellable?

    private init() {
        backdrop.onBackdropClick = { [weak self] in
            Task { @MainActor in await self?.end(reason: .explicit) }
        }
        observers.append(NotificationCenter.default.addObserver(forName: workspaceControlsWindowClosed, object: nil, queue: .main) { [weak self] note in
            guard let id = note.userInfo?["windowId"] as? UInt32 else { return }
            Task { @MainActor in if self?.session?.windowId == id { await self?.end(reason: .invalidated) } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: workspaceControlsWindowInvalidated, object: nil, queue: .main) { [weak self] note in
            guard let id = note.userInfo?["windowId"] as? UInt32 else { return }
            Task { @MainActor in if self?.session?.windowId == id { await self?.end(reason: .invalidated) } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: workspaceControlsWindowDetected, object: nil, queue: .main) { [weak self] note in
            let projectId = note.userInfo?["projectId"] as? WorkspaceProjectId
            let viewportId = note.userInfo?["viewportId"] as? MonitorViewportId
            Task { @MainActor in
                guard let session = self?.session,
                      session.projectId == projectId, session.viewportId == viewportId else { return }
                await self?.end(reason: .invalidated)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.end(reason: .invalidated)
                self?.pendingFloatingRestores.removeAll()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.end(reason: .invalidated) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.end(reason: .invalidated) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor in if self?.session?.pid == pid { await self?.end(reason: .invalidated) } }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor in if self?.session?.pid == pid { await self?.end(reason: .invalidated) } }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor in
                guard let self, let pid else { return }
                let ids = self.pendingFloatingRestores.values.filter { $0.pid == pid }.map(\.windowId)
                for id in ids { await self.restorePendingFloatingFrame(windowId: id) }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: workspaceControlsWindowRestored, object: nil, queue: .main) { [weak self] note in
            guard let id = note.userInfo?["windowId"] as? UInt32 else { return }
            Task { @MainActor in await self?.restorePendingFloatingFrame(windowId: id) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.end(reason: .invalidated) }
        })
        trayObservation = TrayMenuModel.shared.$isEnabled.removeDuplicates().sink { [weak self] enabled in
            guard !enabled else { return }
            Task { @MainActor in await self?.end(reason: .invalidated) }
        }
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }

    var isActive: Bool { session != nil }
    var activeWorkspaceId: WorkspaceId? { session?.workspaceId }
    var activeWindowId: UInt32? { session?.windowId }

    func suppressesChrome(on monitor: Monitor) -> Bool {
        guard let session else { return false }
        return session.viewportId == MonitorViewportId(monitor)
    }

    func suppressesChrome(for window: Window) -> Bool {
        guard let workspace = window.nodeWorkspace else { return false }
        return suppressesChrome(on: workspace.workspaceMonitor)
    }

    func suppressesChrome(workspaceName: String) -> Bool {
        guard let workspace = Workspace.existing(byName: workspaceName) else { return false }
        return suppressesChrome(on: workspace.workspaceMonitor)
    }

    func start(target: Window?, io: CmdIo) async -> Bool {
        guard let window = target as? MacWindow,
              let workspace = workspaceContaining(window),
              workspace.isVisible,
              window.visualWorkspace === workspace,
              !window.isFullscreen,
              window.macApp.nsApp.isTerminated == false,
              !window.isHiddenInCorner,
              let parent = window.parent,
              isOrdinaryManagedParent(parent, child: window) else {
            return io.err("presentation requires a visible, ordinary managed window that is not native fullscreen")
        }
        let sameTargetSession = session?.windowId == window.windowId ? session : nil
        await end(reason: .invalidated)
        let actualRect: Rect
        if let original = sameTargetSession?.originalFrame {
            actualRect = original
        } else if let current = try? await window.getAxRect() {
            actualRect = current
        } else {
            return io.err("presentation could not read the target window frame")
        }
        let savedScrollingState = (workspace.scrollingOffset, workspace.scrollingAnchorWindowId,
            workspace.scrollingAnchorViewportPosition, workspace.scrollingAnchorAreaWidth,
            workspace.lastScrollingFocusWindowId)
        if focus.windowOrNil !== window {
            guard window.focusWindow() else { return io.err("presentation could not focus the target window") }
            window.macApp.nativeFocus(window.windowId, forceRaise: true)
            workspace.scrollingOffset = savedScrollingState.0
            workspace.scrollingAnchorWindowId = savedScrollingState.1
            workspace.scrollingAnchorViewportPosition = savedScrollingState.2
            workspace.scrollingAnchorAreaWidth = savedScrollingState.3
            workspace.lastScrollingFocusWindowId = savedScrollingState.4
        }
        WorkspaceScrollingGestureController.shared.cancelForWorkspaceChange(workspace)
        ScrollingWindowOrdering.shared.cancel()
        WorkspaceScrollingMinimap.shared.dismiss()
        WorkspaceControlsPanelController.shared.dismiss()
        WorkspaceSidebarPanel.visiblePanels.forEach { $0.orderOut(nil) }
        WindowBorderController.shared.remove(windowId: window.windowId)
        WindowTabStripPanelController.shared.hideAll()

        nextEpoch &+= 1
        let epoch = nextEpoch
        let session = Session(epoch: epoch, window: window, windowId: window.windowId,
            pid: window.macApp.pid, launchDate: window.macApp.nsApp.launchDate,
            bundleId: window.macApp.rawAppBundleId, workspace: workspace,
            workspaceId: workspace.id, projectId: workspace.projectId,
            viewportId: MonitorViewportId(workspace.workspaceMonitor),
            displayUUID: workspace.workspaceMonitor.displayUUID,
            originalFrame: actualRect, originalLastAppliedFrame: sameTargetSession?.originalLastAppliedFrame ?? window.lastAppliedLayoutPhysicalRect,
            scrollingOffset: savedScrollingState.0,
            scrollingAnchorWindowId: savedScrollingState.1,
            scrollingAnchorViewportPosition: savedScrollingState.2,
            scrollingAnchorAreaWidth: savedScrollingState.3,
            scrollingFocusWindowId: savedScrollingState.4,
            tiled: !window.isFloating)
        self.session = session
        let presentationRect = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        do {
            try await window.setAxFrameBlocking(presentationRect.topLeftCorner, presentationRect.size)
            guard isCurrent(epoch) else { await end(reason: .invalidated); return false }
            window.lastAppliedLayoutPhysicalRect = presentationRect
            window.lastAppliedLayoutVirtualRect = presentationRect
            let screen = NSScreen.screens.first { $0.displayUUID == session.displayUUID }
            guard let screen else { await end(reason: .invalidated); return false }
            backdrop.setFrame(screen.frame, display: false)
            backdrop.orderFrontRegardless()
            backdrop.orderBehindTarget(windowId: window.windowId)
            installInputCancellation(epoch: epoch)
            return true
        } catch {
            await end(reason: .invalidated)
            return io.err("presentation could not resize the target window: \(error)")
        }
    }

    func end(reason: EndReason) async {
        guard let session = takeSession() else { return }
        await finish(session)
    }

    private func takeSession() -> Session? {
        guard let session else { return nil }
        self.session = nil
        backdrop.orderOut(nil)
        removeInputCancellation()
        return session
    }

    private func finish(_ session: Session) async {
        session.workspace.scrollingOffset = session.scrollingOffset
        session.workspace.scrollingAnchorWindowId = session.scrollingAnchorWindowId
        session.workspace.scrollingAnchorViewportPosition = session.scrollingAnchorViewportPosition
        session.workspace.scrollingAnchorAreaWidth = session.scrollingAnchorAreaWidth
        session.workspace.lastScrollingFocusWindowId = session.scrollingFocusWindowId
        guard self.session?.windowId != session.windowId else { return }
        if MacWindow.allWindowsMap[session.windowId] === session.window,
           session.window.macApp.pid == session.pid,
           session.window.macApp.nsApp.launchDate == session.launchDate,
           session.window.macApp.rawAppBundleId == session.bundleId {
            if session.tiled {
                session.window.lastAppliedLayoutPhysicalRect = nil
                session.window.lastAppliedLayoutVirtualRect = nil
                // Native desktops are laid out after a topology read rather than a refresh.
                if runtime.workspaceBackend.kind == .native {
                    runtime.workspaceBackend.native.observation?.requestRead(event: "presentationEnd")
                } else {
                    scheduleRefreshSession(.globalObserver("presentationEnd"))
                }
            } else if let parent = session.window.parent,
                      isOrdinaryManagedParent(parent, child: session.window),
                      session.workspace.isVisible,
                      MonitorViewportId(session.workspace.workspaceMonitor) == session.viewportId,
                      sortedMonitors.contains(where: { MonitorViewportId($0) == session.viewportId }) {
                try? await session.window.setAxFrameBlocking(session.originalFrame.topLeftCorner,
                    session.originalFrame.size)
                session.window.lastAppliedLayoutPhysicalRect = session.originalLastAppliedFrame
            } else {
                pendingFloatingRestores[session.windowId] = session
                return
            }
            WindowTabStripPanelController.shared.refresh()
            WorkspaceSidebarPanel.refreshAll()
            WindowBorderController.shared.refresh()
        }
    }

    func cancelForFocusChange(to next: LiveFocus) {
        guard let session, session.viewportId == MonitorViewportId(next.workspace.workspaceMonitor),
              next.windowOrNil?.windowId != session.windowId else { return }
        let ending = takeSession()
        Task { @MainActor in if let ending { await finish(ending) } }
    }

    func cancelForMouseManipulation(windowId: UInt32) {
        guard session?.windowId == windowId else { return }
        let ending = takeSession()
        Task { @MainActor in if let ending { await finish(ending) } }
    }

    func cancelForCommand(_ command: any Command) async {
        guard isMutatingPresentationTarget(command) else { return }
        if session != nil { await end(reason: .invalidated) }
        if !(command is MacosNativeFullscreenCommand || command is MacosNativeMinimizeCommand) {
            pendingFloatingRestores.removeAll()
        }
    }

    func restorePendingFloatingFrames(in workspace: Workspace) async {
        let ids = pendingFloatingRestores.values.filter { $0.workspace === workspace }.map(\.windowId)
        for id in ids { await restorePendingFloatingFrame(windowId: id) }
    }

    func restorePendingFloatingFrame(windowId: UInt32) async {
        guard let saved = pendingFloatingRestores[windowId],
              MacWindow.allWindowsMap[windowId] === saved.window,
              saved.window.macApp.pid == saved.pid,
              saved.window.macApp.nsApp.launchDate == saved.launchDate,
              saved.window.macApp.rawAppBundleId == saved.bundleId,
              saved.window.nodeWorkspace === saved.workspace,
              saved.workspace.id == saved.workspaceId,
              saved.workspace.projectId == saved.projectId,
              MonitorViewportId(saved.workspace.workspaceMonitor) == saved.viewportId,
              saved.workspace.isVisible,
              let parent = saved.window.parent,
              isOrdinaryManagedParent(parent, child: saved.window) else { return }
        pendingFloatingRestores.removeValue(forKey: windowId)
        try? await saved.window.setAxFrameBlocking(saved.originalFrame.topLeftCorner, saved.originalFrame.size)
        saved.window.lastAppliedLayoutPhysicalRect = saved.originalLastAppliedFrame
        WorkspaceSidebarPanel.refreshAll()
        WindowTabStripPanelController.shared.refresh()
        WindowBorderController.shared.refresh()
    }

    func preservesLayout(for workspace: Workspace) -> Bool {
        guard let session, session.workspace === workspace else { return false }
        guard isCurrent(session.epoch) else {
            let ending = takeSession()
            Task { @MainActor in if let ending { await finish(ending) } }
            return false
        }
        return true
    }

    private func isCurrent(_ epoch: UInt64) -> Bool {
        guard let session, session.epoch == epoch,
              MacWindow.allWindowsMap[session.windowId] === session.window,
              session.window.macApp.pid == session.pid,
              session.window.macApp.nsApp.launchDate == session.launchDate,
              session.window.macApp.rawAppBundleId == session.bundleId,
              !session.window.macApp.nsApp.isTerminated,
              session.window.nodeWorkspace === session.workspace,
              let parent = session.window.parent,
              isOrdinaryManagedParent(parent, child: session.window),
              session.workspace.id == session.workspaceId,
              session.workspace.projectId == session.projectId,
              session.workspace.isVisible,
              MonitorViewportId(session.workspace.workspaceMonitor) == session.viewportId,
              sortedMonitors.contains(where: { MonitorViewportId($0) == session.viewportId }) else { return false }
        return true
    }

    private func installInputCancellation(epoch: UInt64) {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in if self?.session?.epoch == epoch { await self?.end(reason: .explicit) } }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let session = self.session, session.epoch == epoch,
                      currentlyManipulatedWithMouseWindowId == session.windowId else { return }
                await self.end(reason: .invalidated)
            }
        }
    }

    private func removeInputCancellation() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
    }
}

@MainActor
private func workspaceContaining(_ window: Window) -> Workspace? {
    var node: TreeNode? = window
    while let current = node {
        if let workspace = current as? Workspace { return workspace }
        node = current.parent
    }
    return nil
}

private func isOrdinaryManagedParent(_ parent: NonLeafTreeNodeObject, child: Window) -> Bool {
    switch getChildParentRelationOrNil(child: child, parent: parent) {
    case .tiling, .floatingWindow: true
    default: false
    }
}

private func isMutatingPresentationTarget(_ command: any Command) -> Bool {
    command is LayoutCommand || command is WorkspaceLayoutCommand || command is BalanceSizesCommand ||
        command is ResizeCommand || command is SplitCommand || command is JoinWithCommand ||
        command is StackWithCommand || command is MoveCommand || command is SwapCommand ||
        command is SwapWithMasterCommand || command is FlattenWorkspaceTreeCommand ||
        command is MoveNodeToWorkspaceCommand || command is MoveNodeToProjectCommand ||
        command is MoveNodeToMonitorCommand || command is MoveWorkspaceToMonitorCommand ||
        command is WorkspaceCommand || command is ProjectCommand || command is FullscreenCommand ||
        command is MacosNativeFullscreenCommand || command is MacosNativeMinimizeCommand ||
        command is OpenSidebarCommand || command is ScrollingMinimapCommand
}
