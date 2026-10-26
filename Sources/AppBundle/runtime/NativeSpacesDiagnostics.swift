import Foundation
import NativeSpaces
import ApplicationServices

@MainActor
func nativeSpacesDiagnosticReport() -> String {
    var lines = ["WinMuxX — Native Spaces (experimental read-only)",
        "Automatic tiling, activation, relocation, projects and virtual recovery: unsupported.",
        "No window positions, application focus or macOS settings are changed."]
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
        lines.append("Live ownership preflight (read-only): \(preflight.passed) passed, \(preflight.blocked) blocked; runtime frame writes remain disabled")
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
    return lines.joined(separator: "\n")
}
