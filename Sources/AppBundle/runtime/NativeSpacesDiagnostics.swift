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
    let tiling = runtime.workspaceBackend.nativeTilingEnabled
    var lines = ["WinMuxX — Native Spaces (experimental\(tiling ? " tiling" : " read-only"))",
        "Space switching: workspace N/next/prev via Dock swipe (macOS 27, Accessibility: \(NativeDockSwipe.canPostEvents ? "granted" : "missing")).",
        "Window moves: move-node-to-workspace N/next/prev via bridged SkyLight operation (\(NativeWindowSpaceMover.isAvailable ? "available" : "unavailable on this macOS")).",
        "Space relocation, cross-display moves, projects and virtual recovery: unsupported.",
        nativeSkippedWindowRuleCommands.isEmpty ? "Window rules: floating/tiling applied natively."
            : "Window rules: floating/tiling applied; skipped unsupported: \(nativeSkippedWindowRuleCommands.sorted().joined(separator: "; "))",
        tiling ? "Dwindle/Master tiling is explicitly enabled; no Space or system settings are changed." :
            "No window positions, application focus or macOS settings are changed."]
    lines.append("Tiling: \(runtime.workspaceBackend.nativeTiling.status)")
    lines.append("Last mouse release: \(runtime.workspaceBackend.nativeTiling.lastMouseRelease)")
    let touch = RawWorkspaceTouchSource.shared
    lines.append("Scrolling pan: touch \(touch.status), \(touch.frameCount) frames, max \(touch.maximumFingerCount) fingers; " +
        "last: \(NativeScrollingTouchRouter.shared.lastDecision); fingers: \(NativeScrollingTouchRouter.shared.lastTrace)")
    for monitor in sortedMonitors {
        let shown = runtime.workspaces.visibleWorkspace(for: monitor)
        lines.append("  \(monitor.name): \(shown.map { "\(userFacingWorkspaceName($0)) \($0.arrangement)" } ?? "no desktop bound")")
    }
    lines.append("Native saved layouts pending complete matching: \(runtime.workspaceBackend.nativePersistence.pendingCount)")
    if let error = runtime.workspaceBackend.nativePersistence.lastError { lines.append(error) }
    lines.append("Accessibility permission for this development process: \(AXIsProcessTrusted() ? "available" : "not granted"). Observation does not request it.")
    if let error = lastConfigReloadError { lines.append("Configuration error: \(error)") }
    guard let inventory = runtime.workspaceBackend.observation?.inventory else {
        return (lines + ["Observation has not started."]).joined(separator: "\n")
    }
    lines.append("Status: \(inventory.status)")
    lines.append("AX-classified windows retained in native layout trees: \(MacWindow.allWindows.count)")
    if let milliseconds = runtime.workspaceBackend.nativeWindows.lastDurationMilliseconds {
        lines.append("Last AX reconciliation: \(milliseconds) ms; unclassified candidates: \(runtime.workspaceBackend.nativeWindows.pendingWindowCount); apps over read budget: \(runtime.workspaceBackend.nativeWindows.timedOutAppCount)")
    }
    if let error = runtime.workspaceBackend.nativeWindows.lastError { lines.append("AX reconciliation error: \(error)") }
    if let preflight = runtime.workspaceBackend.nativeWindows.writePreflight {
        lines.append("Live ownership preflight: \(preflight.passed) passed, \(preflight.blocked) blocked; frame writes \(tiling && !serverArgs.isReadOnly ? "require per-write validation" : "remain disabled")")
    }
    lines.append("WindowServer lifecycle events: \(runtime.workspaceBackend.observation?.windowEventsAvailable == true ? "available" : "unavailable; topology/public-event fallback only")")
    if let observer = runtime.workspaceBackend.observation {
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
    for row in nativeWindowFrameDiagnostics(runtime.workspaceBackend.nativeLayouts) {
        if let data = try? encoder.encode(row), let json = String(data: data, encoding: .utf8) {
            lines.append("Window frame: \(json)")
        }
    }
    return lines.joined(separator: "\n")
}
