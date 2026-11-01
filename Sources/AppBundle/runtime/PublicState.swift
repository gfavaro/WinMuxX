import AppKit
import Common

/// JSON-compatible value keeps structured domains extensible without native objects.
indirect enum StateValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), null, array([StateValue]), object([String: StateValue])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([StateValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: StateValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    static func optional(_ s: String?) -> Self { s.map(Self.string) ?? .null }
}

struct PublicStateEnvelope: Codable, Equatable, Sendable {
    var _event = "state-changed"
    var schemaVersion = 1
    let instanceId: String
    let revision: UInt64
    let state: [String: StateValue]
}

@MainActor final class PublicStateStore {
    let instanceId = UUID().uuidString
    private(set) var revision: UInt64 = 0
    var previousMode: String?
    var configRevision: UInt64 = 0
    var transactionDepth = 0
    var publicationTask: Task<Void, Never>?
    var lastPublished: [String: StateValue]?
    var committed: PublicStateEnvelope?
    var structureDirty = true
    var structuralState: [String: StateValue]?
    // UI controllers report state without constructing panels in read-only queries.
    var paletteVisible = false
    var overviewVisible = false
    func changed() { revision &+= 1 }
    isolated deinit { publicationTask?.cancel() }
}

@MainActor func menuBarModeColor(_ presentation: ModePresentation) -> NSColor {
    presentation.color(dark: WorkspaceSidebarPanel.menuBarColorScheme == .dark,
                       increasedContrast: !isUnitTest && NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
}

func stateColorHex(_ color: NSColor) -> String {
    guard let rgb = color.usingColorSpace(.sRGB) else { return "#808080" }
    return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                  Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
}

@MainActor func publicStateSnapshot() -> PublicStateEnvelope {
    let store = runtime.publicState
    if store.transactionDepth > 0, let committed = store.committed { return committed }
    let f = focus
    let focusedMonitor = f.workspace.workspaceMonitor
    let mode = activeMode.flatMap { name in config.modes[name].map { ModePresentation(name: name, mode: $0) } }
    let settings = activeMode.flatMap { config.modes[$0] }
    let suspended = runtime.hotkeys.hotkeysSuspended
    var state: [String: StateValue] = [
        "mode": .object([
            "name": .optional(activeMode), "previousName": .optional(store.previousMode), "initial": .optional(mode?.initial),
            "configuredColor": .optional(settings?.indicatorColor),
            "resolvedColor": .optional(mode.map { stateColorHex(menuBarModeColor($0)) }),
            "indicatorEnabled": .bool(settings?.showIndicator == true && activeMode != mainModeId),
            "indicatorVisible": .bool(TrayMenuModel.shared.modePresentation != nil),
            "timeoutMs": .number(Double(settings?.timeoutMs ?? 0)),
            "exitOnUnboundKey": .bool(settings?.exitOnUnboundKey ?? false),
        ]),
        "runtime": .object([
            "enabled": .bool(TrayMenuModel.shared.isEnabled), "suspended": .bool(suspended),
            "appearance": .string(config.appearance.rawValue),
            "effectiveAppearance": .string(config.appearance == .system ? (WorkspaceSidebarPanel.menuBarColorScheme == .dark ? "dark" : "light") : config.appearance.rawValue),
            "configRevision": .number(Double(store.configRevision)),
        ]),
        "ui": .object([
            "sidebarExpanded": .bool(TrayMenuModel.shared.isWorkspaceSidebarExpanded),
            "sidebarEnabled": .bool(config.workspaceSidebar.enabled),
            "paletteVisible": .bool(store.paletteVisible), "overviewVisible": .bool(store.overviewVisible),
            "sidebarPanels": .array(isUnitTest ? [] : WorkspaceSidebarPanel.visiblePanels.sorted { $0.monitorScopeId < $1.monitorScopeId }.map {
                .object(["scopeId": .string($0.monitorScopeId), "expanded": .bool($0.viewModel.isWorkspaceSidebarExpanded)])
            }),
        ]),
        "focus": .object([
            "windowId": f.windowOrNil.map { .number(Double($0.windowId)) } ?? .null,
            "workspaceId": .string(f.workspace.id.rawValue),
            "monitorUuid": .optional(focusedMonitor.displayUUID),
            "appBundleId": .optional(f.windowOrNil?.app.rawAppBundleId),
            "containerLayout": .optional((f.windowOrNil?.parent as? TilingContainer)?.layout.rawValue),
            "containerOrientation": .optional((f.windowOrNil?.parent as? TilingContainer)?.orientation.rawValue),
        ]),
    ]
    if store.structureDirty || store.structuralState == nil {
    let workspaces = userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: f.workspace)
    state["workspaces"] = .array(workspaces.enumerated().map { index, ws in
        var containers: [StateValue] = []
        func visit(_ node: TreeNode) {
            if let c = node as? TilingContainer {
                containers.append(.object(["layout": .string(c.layout.rawValue), "orientation": .string(c.orientation.rawValue)]))
                for child in c.children { visit(child) }
            }
        }
        visit(ws.rootTilingContainer)
        return .object([
            "id": .string(ws.id.rawValue), "name": .string(ws.name),
            "displayName": .string(workspaceDisplayName(ws.name)), "order": .number(Double(index)),
            "projectId": .string(ws.projectId.rawValue), "persistent": .bool(ws.isConfiguredPersistent),
            "windowCount": .number(Double(ws.allLeafWindowsRecursive.count)),
            "empty": .bool(ws.allLeafWindowsRecursive.isEmpty),
            "activeViewports": .array(runtime.workspaces.monitorViewportsById.values.filter { $0.activeWorkspaceId == ws.id }.map { $0.id.description }.sorted().map(StateValue.string)),
            "layout": .string(ws.rootTilingContainer.layout.rawValue), "containers": .array(containers),
        ])
    })
    state["displays"] = .array(monitors.map { monitor in
        let viewport = runtime.workspaces.monitorViewportsById[MonitorViewportId(monitor)]
        return .object([
            "uuid": .optional(monitor.displayUUID), "index": .number(Double(monitor.monitorId_oneBased ?? 0)),
            "name": .string(monitor.name), "viewportId": .string(MonitorViewportId(monitor).description),
            "focused": .bool(MonitorViewportId(monitor) == MonitorViewportId(focusedMonitor)),
            "workspaceId": .optional(viewport?.activeWorkspaceId?.rawValue),
            "frame": .object(["x": .number(monitor.rect.topLeftX), "y": .number(monitor.rect.topLeftY),
                               "width": .number(monitor.width), "height": .number(monitor.height)]),
        ])
    })
    var windows = Workspace.all.flatMap(\.allLeafWindowsRecursive)
    windows += macosMinimizedWindowsContainer.children.compactMap { $0 as? Window }
    windows += macosPopupWindowsContainer.children.compactMap { $0 as? Window }
    var seen = Set<UInt32>()
    state["windows"] = .array(windows.filter { seen.insert($0.windowId).inserted }.sorted { $0.windowId < $1.windowId }.map { w in
        let kind = w.parent is MacosMinimizedWindowsContainer ? "minimized" :
            w.parent is MacosFullscreenWindowsContainer ? "fullscreen" :
            w.parent is MacosPopupWindowsContainer ? "popup" : w.isFloating ? "floating" : "tiled"
        return .object(["id": .number(Double(w.windowId)), "workspaceId": .optional(w.nodeWorkspace?.id.rawValue),
                        "appBundleId": .optional(w.app.rawAppBundleId), "appName": .optional(w.app.name),
                        "kind": .string(kind), "fullscreen": .bool(w.isFullscreen),
                        "nativeFullscreen": w.lastKnownNativeFullscreen.map(StateValue.bool) ?? .null,
                        "nativeMinimized": w.lastKnownNativeMinimized.map(StateValue.bool) ?? .null])
    })
    state["projects"] = .array(runtime.workspaces.projectsById.values.sorted { $0.order < $1.order }.map {
        .object(["id": .string($0.id.rawValue), "name": .string($0.name), "order": .number(Double($0.order))])
    })
    store.structuralState = Dictionary(uniqueKeysWithValues: ["workspaces", "displays", "windows", "projects"].compactMap { key in state[key].map { (key, $0) } })
    store.structureDirty = false
    } else if let structural = store.structuralState {
        state.merge(structural) { _, new in new }
    }
    // Focused flags belong to focus, even when the structural display cache is reused.
    if case .array(let displays) = state["displays"] {
        state["displays"] = .array(displays.map { value in
            guard case .object(var display) = value else { return value }
            display["focused"] = .bool(display["viewportId"] == .string(MonitorViewportId(focusedMonitor).description))
            return .object(display)
        })
    }
    let snapshot = PublicStateEnvelope(instanceId: store.instanceId, revision: store.revision, state: state)
    store.committed = snapshot
    return snapshot
}

/// No native reads, payload construction or repeating source on this path.
@MainActor func requestPublicStateUpdate(structural: Bool = false) {
    guard runtime.workspaceBackend.capabilities.publishesState else { return }
    let store = runtime.publicState
    store.changed()
    if structural { store.structureDirty = true }
    guard hasPublicStateSubscribers, store.transactionDepth == 0, store.publicationTask == nil else { return }
    let owner = runtime
    store.publicationTask = Task { @MainActor [weak owner] in
        guard let owner else { return }
        owner.withValue {
            store.publicationTask = nil
            guard store.transactionDepth == 0 else { return }
            let snapshot = publicStateSnapshot()
            let changed = store.lastPublished != snapshot.state
            guard changed || hasPendingInitialStateSubscribers else { return }
            store.lastPublished = snapshot.state
            broadcastPublicState(snapshot, changed: changed)
        }
    }
}

@MainActor func hookEnvironment(event: String, previousMode: String? = nil) -> CmdEnv {
    let mode = activeMode.flatMap { name in config.modes[name].map { ModePresentation(name: name, mode: $0) } }
    return CmdEnv(extraEnvironment: [
        "WINMUX_EVENT": event, "WINMUX_MODE": activeMode ?? "", "WINMUX_PREV_MODE": previousMode ?? "",
        "WINMUX_MODE_INITIAL": mode?.initial ?? "", "WINMUX_MODE_COLOR": mode.map { stateColorHex(menuBarModeColor($0)) } ?? "",
        "WINMUX_WORKSPACE": userFacingWorkspaceName(focus.workspace), "WINMUX_WINDOW_ID": focus.windowOrNil.map { String($0.windowId) } ?? "",
        "WINMUX_MONITOR_UUID": focus.workspace.workspaceMonitor.displayUUID ?? "",
        "WINMUX_ENABLED": String(TrayMenuModel.shared.isEnabled), "WINMUX_SUSPENDED": String(runtime.hotkeys.hotkeysSuspended),
        "WINMUX_STATE_REVISION": String(runtime.publicState.revision), "WINMUX_STATE_INSTANCE": runtime.publicState.instanceId,
    ])
}
