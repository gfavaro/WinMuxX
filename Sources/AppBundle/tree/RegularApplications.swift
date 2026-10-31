import AppKit
import Common

/// The running apps with the regular activation policy, kept current by observing the running
/// applications and each one's policy. A full refresh used to ask every running process for
/// its policy, a synchronous LaunchServices request each (about 8 ms for 116 processes) on the
/// main thread, to find the same few apps again.
@MainActor
final class RegularApplications {
    static let shared = RegularApplications()
    private var running: NSKeyValueObservation?
    private var policies: [pid_t: NSKeyValueObservation] = [:]
    private var regular: [pid_t: NSRunningApplication] = [:]

    var all: [NSRunningApplication] {
        if running == nil, !isUnitTest { start() }
        guard running != nil else { return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular } }
        return Array(regular.values)
    }

    private func start() {
        // AppKit changes both properties on the main thread only.
        running = NSWorkspace.shared.observe(\.runningApplications, options: [.initial, .new, .old]) { _, change in
            nonisolated(unsafe) let added = change.newValue ?? []
            nonisolated(unsafe) let removed = change.oldValue ?? []
            MainActor.assumeIsolated {
                for app in removed { RegularApplications.shared.forget(app) }
                for app in added { RegularApplications.shared.watch(app) }
            }
        }
    }

    private func watch(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard policies[pid] == nil else { return }
        policies[pid] = app.observe(\.activationPolicy) { app, _ in
            nonisolated(unsafe) let app = app
            MainActor.assumeIsolated { RegularApplications.shared.update(app) }
        }
        // Read after the observation is stored: an initial callback would arrive before it.
        update(app)
    }

    private func update(_ app: NSRunningApplication) {
        // A pid reused by a later process keeps only that process's entry.
        guard policies[app.processIdentifier] != nil, !app.isTerminated else { return }
        regular[app.processIdentifier] = app.activationPolicy == .regular ? app : nil
    }

    private func forget(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard regular[pid] == nil || regular[pid] === app else { return }
        policies.removeValue(forKey: pid)?.invalidate()
        regular[pid] = nil
    }
}
