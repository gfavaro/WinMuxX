import Foundation
import NativeSpaces
import ApplicationServices

struct NativeWindowFrameDiagnostic: Codable, Equatable {
    let windowID: UInt32
    let pid: Int32
    let spaceUUID: String
    let eligible: Bool
    let floating: Bool
    let desiredFrame: [CGFloat]?
}

@MainActor
func nativeWindowFrameDiagnostics(_ layouts: NativeSpaceLayouts) -> [NativeWindowFrameDiagnostic] {
    layouts.retainedByUUID.flatMap { uuid, workspace in
        workspace.allLeafWindowsRecursive.map { window in
            let frame = window.lastAppliedLayoutPhysicalRect
            return NativeWindowFrameDiagnostic(windowID: window.windowId, pid: window.app.pid,
                spaceUUID: uuid, eligible: window.nativeLayoutEligible, floating: window.parent is Workspace,
                desiredFrame: frame.map { [$0.minX, $0.minY, $0.width, $0.height] })
        }
    }.sorted { $0.windowID < $1.windowID }
}

@MainActor
func nativeSpacesDiagnosticReport() -> String {
    let tiling = runtime.workspaceBackend.native.tilingEnabled
    var lines = ["WinMuxX — Native Spaces (experimental\(tiling ? " tiling" : " read-only"))",
        "Space switching: workspace N/next/prev via Dock swipe (macOS 27, Accessibility: \(NativeDockSwipe.canPostEvents ? "granted" : "missing")).",
        "Window moves: move-node-to-workspace N/next/prev via bridged SkyLight operation (\(NativeWindowSpaceMover.isAvailable ? "available" : "unavailable on this macOS")).",
        "Moves to another display: move-node-to-monitor, and move-workspace-to-monitor moves a desktop's windows and layout (the macOS desktop stays). Projects and virtual recovery: unsupported.",
        nativeSkippedWindowRuleCommands.isEmpty ? "Window rules: floating/tiling applied natively."
            : "Window rules: floating/tiling applied; skipped unsupported: \(nativeSkippedWindowRuleCommands.sorted().joined(separator: "; "))",
        tiling ? "Dwindle/Master tiling is explicitly enabled; no system settings are changed. Desktops are only added, up to persistent-workspaces." :
            "No window positions, application focus or macOS settings are changed."]
    lines += diagnosticsPermissionLines()
    lines.append("Tiling: \(runtime.workspaceBackend.native.tiling.status)")
    if let number = runtime.workspaceBackend.native.desktopTopUp.lastConfirmedCreation { lines.append("Last confirmed desktop creation: \(number)") }
    lines.append("Desktop top-up: \(runtime.workspaceBackend.native.desktopTopUp.status) (creation \(NativeSpaceCreator.isAvailable ? "available" : "unavailable on this macOS"))")
    lines.append("Original frames: \(NativeOriginalFrames.shared.count) kept; last restore: \(NativeOriginalFrames.shared.lastRestore)")
    lines.append("Last mouse release: \(runtime.workspaceBackend.native.tiling.lastMouseRelease)")
    lines.append("Scrolling pan: last \(NativeScrollingPan.shared.lastDecision)")
    let model = TrayMenuModel.shared
    lines.append("Sidebar: enabled \(config.workspaceSidebar.enabled), scopes \(model.workspaceSidebarMonitorScopes.map(\.id)), " +
        "selected \(model.workspaceSidebarSelectedMonitorScopeId), target \(model.workspaceSidebarTargetMonitorScopeId), " +
        "focused \(model.workspaceSidebarFocusedMonitorScopeId)")
    for row in model.workspaceSidebarWorkspaces {
        let items = row.items.map { item -> String in
            switch item.kind {
                case .window(let w): "\(w.windowId) \(w.appName)\(w.isFocused ? "*" : "")"
                case .tabGroup(let g): "tabs[\(g.id)]"
            }
        }
        lines.append("  \(row.displayName) [\(row.monitorScopeId)\(row.isVisible ? ", visible" : "")\(row.isFocused ? ", focused" : "")]: \(items.joined(separator: ", "))")
    }
    lines.append("Chrome refreshes after observations: \(NativeObservationChrome.shared.refreshes) for \(NativeObservationChrome.shared.requests) completed reads")
    lines.append("Windows listed on desktops not showing: \(NativeUnvisitedWindows.shared.bySpaceID.values.map(\.count).reduce(0, +))")
    lines.append("Scrolling pan layouts: \(runtime.workspaceBackend.native.tiling.scrollingLayoutTiming)")
    for monitor in sortedMonitors {
        let shown = runtime.workspaces.visibleWorkspace(for: monitor)
        lines.append("  \(monitor.name): \(shown.map { "\(userFacingWorkspaceName($0)) \($0.arrangement)" } ?? "no desktop bound")")
    }
    lines.append("Native saved layouts pending complete matching: \(runtime.workspaceBackend.native.persistence.pendingCount)")
    if let error = runtime.workspaceBackend.native.persistence.lastError { lines.append(error) }
    lines.append("Accessibility permission for this development process: \(AXIsProcessTrusted() ? "available" : "not granted"). Observation does not request it.")
    if let error = lastConfigReloadError { lines.append("Configuration error: \(error)") }
    guard let inventory = runtime.workspaceBackend.native.observation?.inventory else {
        return (lines + ["Observation has not started."]).joined(separator: "\n")
    }
    lines.append("Status: \(inventory.status)")
    lines.append("AX-classified windows retained in native layout trees: \(MacWindow.allWindows.count)")
    if let milliseconds = runtime.workspaceBackend.native.windows.lastDurationMilliseconds {
        lines.append("Last AX reconciliation: \(milliseconds) ms; unclassified candidates: \(runtime.workspaceBackend.native.windows.pendingWindowCount); apps over read budget: \(runtime.workspaceBackend.native.windows.timedOutAppCount)")
    }
    if let error = runtime.workspaceBackend.native.windows.lastError { lines.append("AX reconciliation error: \(error)") }
    if let preflight = runtime.workspaceBackend.native.windows.writePreflight {
        lines.append("Live ownership preflight: \(preflight.passed) passed, \(preflight.blocked) blocked; frame writes \(tiling && !serverArgs.isReadOnly ? "require per-write validation" : "remain disabled")")
    }
    lines.append("WindowServer lifecycle events: \(runtime.workspaceBackend.native.observation?.windowEventsAvailable == true ? "available" : "unavailable; topology/public-event fallback only")")
    if let observer = runtime.workspaceBackend.native.observation {
        lines.append("Reads: \(observer.snapshotReadCount) snapshots; \(observer.topologyAuditCount) topology audits; \(observer.windowEventCount) WindowServer events")
        if let milliseconds = observer.lastTopologyAuditMilliseconds { lines.append("Last topology-only audit: \(milliseconds) ms") }
    }
    guard let snapshot = inventory.lastSnapshot else { return lines.joined(separator: "\n") }
    if inventory.currentSnapshot == nil { lines.append("STALE: the retained snapshot cannot authorize management.") }
    lines.append("Captured: \(snapshot.capturedAt.ISO8601Format()); query: \(snapshot.readMilliseconds) ms")
    if let targets = snapshot.reconciliationSpaceIDs { lines.append("Reconciliation Spaces: \(targets.joined(separator: ", "))") }
    for display in snapshot.displays {
        lines.append("Display \(display.identifier): active Space \(display.activeSpaceID)")
        for (index, space) in display.spaces.enumerated() {
            lines.append("  \(index + 1): id=\(space.id), uuid=\(space.uuid ?? "unavailable"), type=\(space.type)\(space.isDesktop ? " desktop" : " unmanaged")")
        }
    }
    let known = snapshot.windows.filter { $0.unambiguousSpaceID != nil }.count
    lines.append("Window inventory: \(snapshot.windows.count); single-Space memberships: \(known). Inventory entries are not necessarily manageable AX windows.")
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    for row in nativeWindowFrameDiagnostics(runtime.workspaceBackend.native.layouts) {
        if let data = try? encoder.encode(row), let json = String(data: data, encoding: .utf8) {
            lines.append("Window frame: \(json)")
        }
    }
    return lines.joined(separator: "\n")
}
