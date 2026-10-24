import AppKit
import Common

/// Bounded submission timings, not measurements of pixels presented by WindowServer.
@MainActor
enum WorkspaceMotionDiagnostics {
    static let capacity = 128
    private(set) static var samples: [String: [Double]] = [:]
    private static var pending: [MonitorViewportId: (workspace: WorkspaceId, start: Double)] = [:]

    static func record(_ stage: String, milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        var values = samples[stage, default: []]
        values.append(milliseconds)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
        samples[stage] = values
    }

    static func selected(_ workspace: Workspace) {
        guard !isUnitTest else { return }
        // Only the latest selection on a display can reach layout readiness.
        let connected = Set(sortedMonitors.map { MonitorViewportId($0) })
        pending = pending.filter { connected.contains($0.key) }
        pending[MonitorViewportId(workspace.workspaceMonitor)] = (workspace.id, CACurrentMediaTime())
    }

    static func layoutReady(_ workspace: Workspace) {
        let id = MonitorViewportId(workspace.workspaceMonitor)
        guard let entry = pending[id], entry.workspace == workspace.id else { return }
        pending[id] = nil
        record("Workspace selection to layout ready", milliseconds: (CACurrentMediaTime() - entry.start) * 1000)
    }
}
