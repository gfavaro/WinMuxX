import Foundation
import NativeSpaces

@MainActor
func nativeSpacesDiagnosticReport() -> String {
    var lines = ["WinMuxX — Native Spaces (experimental read-only)",
        "Automatic tiling, activation, relocation, projects and virtual recovery: unsupported.",
        "No window positions, application focus or macOS settings are changed."]
    if let error = lastConfigReloadError { lines.append("Configuration error: \(error)") }
    guard let inventory = runtime.workspaceBackend.observation?.inventory else {
        return (lines + ["Observation has not started."]).joined(separator: "\n")
    }
    lines.append("Status: \(inventory.status)")
    guard let snapshot = inventory.lastSnapshot else { return lines.joined(separator: "\n") }
    if inventory.currentSnapshot == nil { lines.append("STALE: the retained snapshot cannot authorize management.") }
    lines.append("Captured: \(snapshot.capturedAt.ISO8601Format()); query: \(snapshot.readMilliseconds) ms")
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
