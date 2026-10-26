import AppKit
import Combine
import Common
import SwiftUI

struct WorkspaceControlsGroup: Identifiable {
    let id: Int
    let title: String
    let frame: CGRect?
    let icons: [NSImage]
    let focusedWindowId: UInt32?
}

struct WorkspaceControlsSnapshot {
    let workspaceId: WorkspaceId
    let viewportId: MonitorViewportId
    let workspaceName: String
    let projectName: String
    let displayName: String
    let arrangement: WorkspaceLayoutName
    let enabled: Bool
    let viewport: CGRect
    let groups: [WorkspaceControlsGroup]
    let fitIssues: [WorkspaceFitIssue]
    let generation: UInt64
    let targetWindowId: UInt32?

    func withGeneration(_ value: UInt64) -> WorkspaceControlsSnapshot {
        WorkspaceControlsSnapshot(workspaceId: workspaceId, viewportId: viewportId, workspaceName: workspaceName,
            projectName: projectName, displayName: displayName, arrangement: arrangement, enabled: enabled,
            viewport: viewport, groups: groups, fitIssues: fitIssues, generation: value, targetWindowId: targetWindowId)
    }
}

@MainActor
final class WorkspaceControlsPanelController: NSObject {
    static let shared = WorkspaceControlsPanelController()

    private let panel = NSPanelHud()
    private var model: WorkspaceControlsPanelModel?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?
    private var notificationTokens: [NSObjectProtocol] = []
    private var capturedFocus: LiveFocus?
    private var capturedWindow: MacWindow?
    private var capturedPid: Int32?
    private var capturedLaunchDate: Date?
    private var capturedBundleId: String?
    private var capturedWorkspaceId: WorkspaceId?
    private var capturedProjectId: WorkspaceProjectId?
    private var capturedViewportId: MonitorViewportId?
    private var capturedGeneration: UInt64 = 0
    private var trayObservation: AnyCancellable?
    private var globalMonitors: [Any?] = []

    private override init() {
        super.init()
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.setContentSize(NSSize(width: 380, height: 560))
        notificationTokens.append(NotificationCenter.default.addObserver(forName: workspaceControlsFocusChanged, object: nil, queue: .main) { [weak self] notification in
            let workspaceId = notification.userInfo?["workspaceId"] as? WorkspaceId
            let windowId = notification.userInfo?["windowId"] as? UInt32
            Task { @MainActor in self?.focusDidChange(workspaceId: workspaceId, windowId: windowId) }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: workspaceControlsWindowClosed, object: nil, queue: .main) { [weak self] notification in
            let windowId = notification.userInfo?["windowId"] as? UInt32
            Task { @MainActor in
                guard let self, windowId == self.capturedWindow?.windowId else { return }
                self.dismiss()
            }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: workspaceControlsWindowInvalidated, object: nil, queue: .main) { [weak self] notification in
            let windowId = notification.userInfo?["windowId"] as? UInt32
            Task { @MainActor in
                guard let self, windowId == self.capturedWindow?.windowId else { return }
                self.dismiss()
            }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: workspaceControlsWindowDetected, object: nil, queue: .main) { [weak self] notification in
            let projectId = notification.userInfo?["projectId"] as? WorkspaceProjectId
            let viewportId = notification.userInfo?["viewportId"] as? MonitorViewportId
            Task { @MainActor in
                guard let self, projectId == self.capturedProjectId, viewportId == self.capturedViewportId else { return }
                self.dismiss()
            }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: workspaceControlsOwnershipChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        })
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        })
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        })
    }

    isolated deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        globalMonitors.compactMap { $0 }.forEach(NSEvent.removeMonitor)
    }

    func toggle() {
        if panel.isVisible { dismiss() } else { show() }
    }

    func dismiss() {
        panel.orderOut(nil)
        model = nil
        capturedFocus = nil
        capturedWindow = nil
        capturedPid = nil
        capturedLaunchDate = nil
        capturedBundleId = nil
        capturedWorkspaceId = nil
        capturedProjectId = nil
        capturedViewportId = nil
        trayObservation = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor); self.outsideClickMonitor = nil }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        globalMonitors.compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitors = []
    }

    func show() {
        guard makeSnapshot() != nil else { return }
        dismiss()
        guard let fresh = makeSnapshot() else { return }
        capturedFocus = focus
        capturedWindow = focus.windowOrNil as? MacWindow
        capturedPid = capturedWindow?.macApp.pid
        capturedLaunchDate = capturedWindow?.macApp.nsApp.launchDate
        capturedBundleId = capturedWindow?.macApp.rawAppBundleId
        capturedWorkspaceId = focus.workspace.id
        capturedProjectId = focus.workspace.projectId
        capturedViewportId = MonitorViewportId(focus.workspace.workspaceMonitor)
        capturedGeneration &+= 1
        let generation = capturedGeneration
        let panelModel = WorkspaceControlsPanelModel(snapshot: fresh.withGeneration(generation), controller: self)
        model = panelModel
        trayObservation = TrayMenuModel.shared.$isEnabled.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible, let model = self.model,
                      self.isCurrent(generation: generation) else { return }
                model.snapshot = self.makeSnapshot(generation: generation) ?? model.snapshot
            }
        }
        panel.contentView = NSHostingView(rootView: WorkspaceControlsPanelView(model: panelModel))
        let screen = NSScreen.screens.first { $0.displayUUID == focus.workspace.workspaceMonitor.displayUUID } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 900, height: 700)
        let origin = CGPoint(x: frame.maxX - 396, y: frame.maxY - 570)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        installDismissMonitors()
    }

    private func installDismissMonitors() {
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            let point = NSEvent.mouseLocation
            if !self.panel.frame.contains(point), !NativeActionMenu.shared.containsStatusItem(point: point) {
                Task { @MainActor in self.dismiss() }
            }
            return event
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.dismiss() } }
            return event
        }
        let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let point = NSEvent.mouseLocation
                if !self.panel.frame.contains(point), !NativeActionMenu.shared.containsStatusItem(point: point) { self.dismiss() }
            }
        }
        let escape = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.dismiss() } }
        }
        globalMonitors = [outside, escape]
    }

    private func focusDidChange(workspaceId: WorkspaceId?, windowId: UInt32?) {
        guard panel.isVisible else { return }
        guard workspaceId == capturedWorkspaceId else { dismiss(); return }
        if let target = capturedWindow, windowId != target.windowId,
           let current = focus.windowOrNil as? MacWindow,
           current.macApp.pid != capturedPid || current.macApp.nsApp.launchDate != capturedLaunchDate {
            dismiss()
            return
        }
    }

    func isCurrent() -> Bool {
        isCurrent(generation: capturedGeneration)
    }

    private func isCurrent(generation: UInt64) -> Bool {
        guard generation == capturedGeneration,
              let capturedWorkspaceId, focus.workspace.id == capturedWorkspaceId,
              let capturedViewportId,
              MonitorViewportId(focus.workspace.workspaceMonitor) == capturedViewportId,
              sortedMonitors.contains(where: { MonitorViewportId($0) == capturedViewportId }) else { return false }
        if let window = capturedWindow {
            guard MacWindow.allWindowsMap[window.windowId] === window,
                  window.macApp.pid == capturedPid, window.macApp.nsApp.launchDate == capturedLaunchDate,
                  window.macApp.rawAppBundleId == capturedBundleId, !window.macApp.nsApp.isTerminated,
                  workspaceContaining(window)?.id == capturedWorkspaceId else { return false }
        }
        return true
    }

    func perform(_ script: String, explicitWindowId: UInt32? = nil) {
        let generation = capturedGeneration
        guard isCurrent(generation: generation), let model, case .cmd(let command) = parseCommand(script) else { dismiss(); return }
        let environment = explicitWindowId.map { CmdEnv(windowId: $0) } ?? capturedFocus.map(CmdEnv.defaultEnv.withFocus) ?? .defaultEnv
        Task { @MainActor in
            do {
                guard let token: RunSessionGuard = RunSessionGuard.isServerEnabled(orIsEnableCommand: command) else { return }
                try await runLightSession(.menuBarButton, token, shouldSchedulePostRefresh: !command.canSkipPostCommandRefresh) {
                    let result = try await [command].runCmdSeq(environment, .emptyStdin)
                    if result.exitCode != 0 {
                        MessageModel.shared.message = Message(description: "Workspace Controls", body: (result.stderr + result.stdout).joined(separator: "\n"))
                    }
                }
                guard isCurrent(generation: generation) else { dismiss(); return }
                model.snapshot = makeSnapshot(generation: generation) ?? model.snapshot
            } catch {
                MessageModel.shared.message = Message(description: "Workspace Controls", body: String(describing: error))
            }
        }
    }

    func openSettings() {
        dismiss()
        UserDefaults.standard.set("windows", forKey: "settings.selectedPage")
        ShortcutSettingsModel.shared.requestWindowOpen()
    }

    func createQuickRule(match: QuickFloatingRuleMatch?) {
        guard isCurrent(), let capturedFocus else { dismiss(); return }
        dismiss()
        NativeActionMenu.shared.createQuickFloatingRule(for: capturedFocus, match: match)
    }

    func openMoreActions() {
        dismiss()
        NativeActionMenu.shared.openMenu()
    }

    func makeSnapshot(generation: UInt64 = 0) -> WorkspaceControlsSnapshot? {
        if case .macosFullscreenWindowsContainer(_) = focus.windowOrNil?.parent?.cases { return nil }
        let workspace = focus.workspace
        let visibleRect = workspace.workspaceMonitor.visibleRect
        let viewport = CGRect(x: visibleRect.topLeftX, y: visibleRect.topLeftY, width: visibleRect.width, height: visibleRect.height)
        let groups = workspace.workspaceLayoutUnits.enumerated().map { index, group -> WorkspaceControlsGroup in
            let windows = group.allLeafWindowsRecursive
            let frame = group.lastAppliedLayoutPhysicalRect.map { CGRect(x: $0.topLeftX, y: $0.topLeftY, width: $0.width, height: $0.height) }
            let rememberedId = windows.contains(where: { $0.windowId == workspace.lastScrollingFocusWindowId }) ? workspace.lastScrollingFocusWindowId : nil
            let selectedId = focus.workspace === workspace ? focus.windowOrNil?.windowId : nil
            let target = selectedId.flatMap { id in windows.first { $0.windowId == id } }
                ?? rememberedId.flatMap { id in windows.first { $0.windowId == id } }
                ?? windows.first
            let title = target.map { ($0.app.name ?? $0.app.rawAppBundleId ?? "Window") + (windows.count > 1 ? " · \(windows.count) windows" : "") } ?? "Group \(index + 1)"
            let icons = windows.prefix(4).compactMap { window -> NSImage? in
                guard let id = window.app.rawAppBundleId,
                      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return WorkspaceControlsGroup(id: index, title: title, frame: frame, icons: icons, focusedWindowId: target?.windowId)
        }
        return WorkspaceControlsSnapshot(workspaceId: workspace.id,
            viewportId: MonitorViewportId(workspace.workspaceMonitor), workspaceName: workspaceDisplayName(workspace.name),
        projectName: workspaceProjectDisplayName(workspace.projectId, fallbackName: workspace.projectId.rawValue),
            displayName: workspace.workspaceMonitor.name, arrangement: workspace.arrangement,
            enabled: TrayMenuModel.shared.isEnabled, viewport: viewport, groups: groups,
            fitIssues: workspaceFitIssues(in: [workspace]), generation: generation,
            targetWindowId: focus.windowOrNil?.windowId)
    }

    private func workspaceContaining(_ window: Window) -> Workspace? {
        var node: TreeNode? = window
        while let current = node {
            if let workspace = current as? Workspace { return workspace }
            node = current.parent
        }
        return nil
    }
}

@MainActor
final class WorkspaceControlsPanelModel: ObservableObject {
    @Published var snapshot: WorkspaceControlsSnapshot
    private weak var controller: WorkspaceControlsPanelController?

    init(snapshot: WorkspaceControlsSnapshot, controller: WorkspaceControlsPanelController) {
        self.snapshot = snapshot
        self.controller = controller
    }

    func perform(_ script: String, windowId: UInt32? = nil) { controller?.perform(script, explicitWindowId: windowId) }
    func controllerQuickRule(_ match: QuickFloatingRuleMatch?) { controller?.createQuickRule(match: match) }
    func settings() { controller?.openSettings() }
    func more() { controller?.openMoreActions() }
    func dismiss() { controller?.dismiss() }
}

struct WorkspaceControlsPanelView: View {
    @ObservedObject var model: WorkspaceControlsPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !model.snapshot.enabled {
                Text("WinMuxX is disabled. Enable window management to use workspace controls.")
                    .font(.callout).foregroundStyle(.secondary)
                button("Enable WinMuxX", "enable on")
            } else {
                preview
                groupButtons
                arrangementActions
                focusedWindowActions
                if model.snapshot.targetWindowId != nil { contextualFloatingActions }
                if !model.snapshot.fitIssues.isEmpty { diagnostics }
            }
            HStack {
                button("Settings…", action: model.settings)
                Spacer()
                button("More Actions…", action: model.more)
            }
        }
        .padding(14)
        .frame(width: 380, height: 560, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.snapshot.workspaceName).font(.headline)
                Text("\(model.snapshot.projectName) · \(model.snapshot.displayName) · \(model.snapshot.arrangement.rawValue.capitalized)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(model.snapshot.enabled ? "Enabled" : "Disabled", systemImage: model.snapshot.enabled ? "checkmark.circle.fill" : "pause.circle.fill")
                .font(.caption).foregroundStyle(model.snapshot.enabled ? .green : .secondary)
            Image(systemName: "rectangle.3.group").foregroundStyle(.secondary)
        }
    }

    private var preview: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08))
            ForEach(model.snapshot.groups) { group in
                    if let frame = group.frame, frame.intersects(model.snapshot.viewport) {
                        let clipped = frame.intersection(model.snapshot.viewport)
                        let scale = min((geometry.size.width - 16) / max(model.snapshot.viewport.width, 1),
                                       (geometry.size.height - 16) / max(model.snapshot.viewport.height, 1))
                        let x = (clipped.minX - model.snapshot.viewport.minX) * scale + 8
                        let y = (clipped.minY - model.snapshot.viewport.minY) * scale + 8
                        let width = max(32, clipped.width * scale)
                        let height = max(32, clipped.height * scale)
                        Button { if let windowId = group.focusedWindowId { model.perform("focus --window-id \(windowId)", windowId: windowId) } } label: {
                            VStack(spacing: 2) {
                                iconStrip(group.icons)
                                Text(group.title).font(.system(size: 9)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(group.focusedWindowId == focus.windowOrNil?.windowId ? Color.accentColor.opacity(0.3) : Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.22)))
                        }
                        .buttonStyle(.plain)
                        .frame(width: min(width, geometry.size.width - 16), height: min(height, geometry.size.height - 16))
                        .offset(x: min(max(8, x), geometry.size.width - 40), y: min(max(8, y), geometry.size.height - 40))
                        .accessibilityLabel(group.title)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: 118)
        .overlay(alignment: .bottomTrailing) {
            if model.snapshot.arrangement == .scrolling {
                HStack(spacing: 3) { Image(systemName: "chevron.left"); Capsule().frame(width: 24, height: 3); Image(systemName: "chevron.right") }
                    .font(.system(size: 8, weight: .semibold)).padding(5).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Current workspace group layout preview")
    }

    private var groupButtons: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(model.snapshot.groups) { group in
                    Button { if let id = group.focusedWindowId { model.perform("focus --window-id \(id)", windowId: id) } } label: {
                        HStack(spacing: 5) { iconStrip(group.icons); Text(group.title).lineLimit(1) }
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Focus \(group.title)")
                }
            }
        }
        .frame(height: 40)
    }

    private var arrangementActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Arrangement").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                button("Dwindle", "workspace-layout dwindle")
                button("Tiles", "workspace-layout tiles")
                button("Master", "workspace-layout master")
                button("Scroll", "workspace-layout scrolling")
            }
            HStack(spacing: 5) {
                button("Balance", "balance-sizes")
                if model.snapshot.arrangement == .scrolling {
                    button("Width −", "scrolling-width previous")
                    button("Width +", "scrolling-width next")
                    button("Center", "scrolling-center")
                }
            }
        }
    }

    private var focusedWindowActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focused window").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                button("Float", "layout floating").disabled(model.snapshot.targetWindowId == nil)
                button("Tile", "layout tiling").disabled(model.snapshot.targetWindowId == nil)
                button("Fullscreen", "fullscreen").disabled(model.snapshot.targetWindowId == nil)
                button("Present", "presentation toggle").disabled(model.snapshot.targetWindowId == nil)
            }
        }
    }

    private var contextualFloatingActions: some View {
        HStack(spacing: 5) {
            button("Always Float App…", action: { model.controllerQuickRule(.application) })
            button("Floating Rule…", action: { model.controllerQuickRule(nil) })
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Fit diagnostics").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(model.snapshot.fitIssues.map { $0.kind == .tiledGroup ? "Group minimum exceeds layout area" : "Scrolling column minimum exceeds viewport" }.joined(separator: "\n"))
                .font(.caption).lineLimit(2).foregroundStyle(.secondary)
            HStack {
                button("Float window", "layout floating")
                button("View learned min", action: model.settings)
            }
        }
        .padding(8)
        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func button(_ title: String, _ script: String) -> some View {
        Button(title) { model.perform(script) }.buttonStyle(.bordered).controlSize(.small)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.bordered).controlSize(.small)
    }

    private func iconStrip(_ icons: [NSImage]) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(icons.prefix(3).enumerated()), id: \.offset) { _, icon in
                Image(nsImage: icon).resizable().frame(width: 12, height: 12)
            }
        }
    }
}

let workspaceControlsFocusChanged = Notification.Name("WinMuxWorkspaceControlsFocusChanged")
let workspaceControlsWindowClosed = Notification.Name("WinMuxWorkspaceControlsWindowClosed")
let workspaceControlsWindowInvalidated = Notification.Name("WinMuxWorkspaceControlsWindowInvalidated")
let workspaceControlsWindowDetected = Notification.Name("WinMuxWorkspaceControlsWindowDetected")
let workspaceControlsOwnershipChanged = Notification.Name("WinMuxWorkspaceControlsOwnershipChanged")
let workspaceControlsWindowRestored = Notification.Name("WinMuxWorkspaceControlsWindowRestored")
