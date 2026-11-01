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

    var all: [NSRunningApplication] { byPid.map(\.value) }

    /// Keyed by pid, so callers need not ask each app for it: after every app activation AppKit
    /// fetches even `processIdentifier` again from LaunchServices, once per app.
    var byPid: [pid_t: NSRunningApplication] {
        if running == nil, !isUnitTest { start() }
        guard running != nil else {
            return Dictionary(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                .map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return regular
    }

    func isRegular(_ pid: pid_t) -> Bool {
        running == nil ? NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular : regular[pid] != nil
    }

    /// Whether this app is still running, from the observed running applications.
    func isRunning(_ app: NSRunningApplication, pid: pid_t) -> Bool {
        guard running != nil else { return !app.isTerminated }
        return policies[pid] != nil && (regular[pid].map { isSameRunningProcess($0, app) } ?? true)
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
        guard regular[pid].map({ isSameRunningProcess($0, app) }) ?? true else { return }
        policies.removeValue(forKey: pid)?.invalidate()
        regular[pid] = nil
    }
}

/// AppKit returns a different `NSRunningApplication` object for the same process depending on
/// where it came from (`frontmostApplication`, `runningApplications`, a pid lookup), so object
/// identity cannot tell whether two refer to one process. Equality can: it is per process, so a
/// pid reused by a later process is still a different app.
func isSameRunningProcess(_ lhs: NSRunningApplication, _ rhs: NSRunningApplication) -> Bool {
    lhs === rhs || lhs.isEqual(rhs)
}
