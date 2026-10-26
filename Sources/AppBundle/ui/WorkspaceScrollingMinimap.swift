import AppKit
import Common

func scrollingMinimapFrame(size: CGSize, visibleFrames: [CGRect], screenIndex: Int) -> CGRect? {
    guard visibleFrames.indices.contains(screenIndex - 1) else { return nil }
    let screen = visibleFrames[screenIndex - 1]
    return CGRect(x: screen.midX - size.width / 2, y: screen.minY + 32, width: size.width, height: size.height)
}

@MainActor
final class WorkspaceScrollingMinimap: NSObject {
    static let shared = WorkspaceScrollingMinimap()
    private var panel: NSPanel?
    private var view: ScrollingMinimapView?
    private weak var workspace: Workspace?
    private var dismissTask: Task<Void, Never>?
    private var titleTask: Task<Void, Never>?
    private var representativeIDs: [UInt32] = []
    private var icons: [Int32: NSImage] = [:]
    private var lifetime = ScrollingMinimapLifetime()
    private var generation: UInt64 = 0
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    @discardableResult
    func show(_ workspace: Workspace, duringGesture: Bool = false, explicitly: Bool = false) -> Bool {
        guard config.scrolling.minimapEnabled, workspace.arrangement == .scrolling,
              workspace.isVisible, !workspace.workspaceLayoutUnits.isEmpty,
              TrayMenuModel.shared.isEnabled, !WorkspaceOverviewController.shared.isOpen,
              !WindowBorderController.shared.isMissionControlActive, !isMouseManipulationActive else { return false }
        guard focus.windowOrNil?.isFullscreen != true,
              focus.windowOrNil?.lastKnownNativeFullscreen != true else { dismiss(); return false }
        if isUnitTest { return true }
        if self.workspace !== workspace {
            dismiss()
            self.workspace = workspace
        }
        lifetime.activity(at: now)
        if explicitly { lifetime.openExplicitly(at: now) }
        if duringGesture { lifetime.pan(true, at: now) }
        render(workspace)
        guard self.workspace === workspace else { return false }
        panel?.alphaValue = 1
        if explicitly {
            panel?.makeKeyAndOrderFront(nil)
            view?.beginKeyboardNavigation()
        } else {
            panel?.orderFrontRegardless()
        }
        scheduleDismissal()
        return true
    }

    func endGesture() {
        lifetime.pan(false, at: now)
        modelDidChange()
        scheduleDismissal()
    }

    func modelDidChange() {
        guard panel?.isVisible == true else { return }
        guard let workspace, workspace.arrangement == .scrolling, workspace.isVisible, !workspace.workspaceLayoutUnits.isEmpty,
              config.scrolling.minimapEnabled, TrayMenuModel.shared.isEnabled,
              !WorkspaceOverviewController.shared.isOpen,
              !WindowBorderController.shared.isMissionControlActive,
              focus.windowOrNil?.isFullscreen != true,
              focus.windowOrNil?.lastKnownNativeFullscreen != true else { dismiss(); return }
        render(workspace)
    }

    func dismiss() {
        generation &+= 1
        dismissTask?.cancel()
        dismissTask = nil
        titleTask?.cancel()
        titleTask = nil
        representativeIDs = []
        icons = [:]
        lifetime = ScrollingMinimapLifetime()
        view?.resetPresentation()
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        workspace = nil
    }

    var isExplicitlyOpen: Bool { lifetime.isExplicitlyOpen }

    private func render(_ workspace: Workspace) {
        let screens = NSScreen.screens
        let index = workspace.workspaceMonitor.monitorAppKitNsScreenScreensId
        guard screens.indices.contains(index - 1) else { dismiss(); return }
        let width = min(680, max(240, screens[index - 1].visibleFrame.width - 48))
        let height = scrollingMinimapRowHeight(metrics: workspace.scrollingMetrics) + 62
        guard let frame = scrollingMinimapFrame(size: CGSize(width: width, height: height),
            visibleFrames: screens.map(\.visibleFrame), screenIndex: index) else { dismiss(); return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(frame.size)
        panel.setFrameOrigin(frame.origin)
        let view: ScrollingMinimapView
        if let existing = self.view { view = existing }
        else {
            let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
            effect.autoresizingMask = [.width, .height]
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 14
            effect.layer?.masksToBounds = true
            if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                effect.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            view = ScrollingMinimapView(frame: effect.bounds)
            view.autoresizingMask = [.width, .height]
            view.selected = { [weak self] id in self?.selectGroup(id) }
            view.hoverChanged = { [weak self] hovered in
                guard let self else { return }
                self.lifetime.hover(hovered, at: self.now)
                self.panel?.alphaValue = 1
                self.scheduleDismissal()
            }
            view.dismissRequested = { [weak self] in self?.dismiss() }
            effect.addSubview(view)
            panel.contentView = effect
            self.view = view
        }
        view.frame = CGRect(origin: .zero, size: frame.size)
        let expectedEpoch = workspace.scrollingSessionEpoch
        let expectedTopology = workspace.scrollingTopologySignature
        view.selected = { [weak self, weak workspace] id in
            guard let self, let workspace, self.workspace === workspace,
                  workspace.scrollingSessionEpoch == expectedEpoch,
                  workspace.scrollingTopologySignature == expectedTopology,
                  workspace.isVisible else { return }
            self.selectGroup(id)
        }
        let groups = workspace.workspaceLayoutUnits
        let representatives = groups.compactMap(\.mostRecentWindowRecursive)
        let models = groups.map { group -> ScrollingMinimapTile in
            let windows = group.allLeafWindowsRecursive
            let window = group.mostRecentWindowRecursive
            var pids: [Int32] = []
            for member in windows where !pids.contains(member.app.pid) {
                pids.append(member.app.pid)
                if icons[member.app.pid] == nil {
                    icons[member.app.pid] = (member.app as? MacApp)?.nsApp.icon
                        ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
                }
            }
            return ScrollingMinimapTile(id: ObjectIdentifier(group),
                title: window.flatMap { cachedWindowTitle(for: $0) ?? $0.app.name } ?? "Empty group",
                applications: pids, count: windows.count,
                tabs: (group as? TilingContainer)?.layout == .tabGroup,
                horizontalSplit: (group as? TilingContainer)?.orientation == .h)
        }
        view.update(workspaceName: workspaceDisplayName(workspace.name), models: models, icons: icons,
                    metrics: workspace.scrollingMetrics, offset: workspace.scrollingOffset,
                    focused: focus.windowOrNil.flatMap { $0.nodeWorkspace === workspace ? ObjectIdentifier($0.topLevelWorkspaceGroup) : nil })
        refreshTitles(representatives, in: workspace)
    }

    private func refreshTitles(_ windows: [Window], in workspace: Workspace) {
        let windows = Array(windows.prefix(32))
        let ids = windows.map(\.windowId)
        guard representativeIDs != ids else { return }
        representativeIDs = ids
        titleTask?.cancel()
        let expected = generation
        titleTask = Task { @MainActor [weak self, weak workspace] in
            for window in windows {
                guard !Task.isCancelled, self?.generation == expected else { return }
                _ = await getSessionWindowTitle(window)
            }
            guard !Task.isCancelled, let self, let workspace, self.generation == expected,
                  self.workspace === workspace else { return }
            self.titleTask = nil
            self.modelDidChange()
        }
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.alphaValue = 1
        guard workspace != nil, let delay = lifetime.dismissalDelay(at: now) else { return }
        let expected = generation
        dismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.generation == expected, !Task.isCancelled,
                  self.lifetime.dismissalDelay(at: self.now) == 0 else { return }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                for step in 1...8 {
                    guard !Task.isCancelled, self.generation == expected else { return }
                    self.panel?.alphaValue = 1 - CGFloat(step) / 8
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                }
            }
            guard !Task.isCancelled, self.generation == expected else { return }
            self.dismiss()
        }
    }

    private func selectGroup(_ id: ObjectIdentifier) {
        guard let workspace, focusScrollingMinimapGroup(id, in: workspace) else { dismiss(); return }
        show(workspace)
    }

    private func makePanel() -> NSPanel {
        let panel = ScrollingMinimapPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "Scrolling workspace minimap"
        panel.identifier = NSUserInterfaceItemIdentifier("WinMux.scrollingMinimap")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        return panel
    }
}

@MainActor
private final class ScrollingMinimapPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
