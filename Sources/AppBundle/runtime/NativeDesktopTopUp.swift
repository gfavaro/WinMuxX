import Common
import NativeSpaces

/// Adds the desktops `persistent-workspaces` numbers that macOS lacks, one per
/// completed topology read, so each step plans from what macOS actually did. New
/// desktops go to the display `workspace-to-monitor-force-assignment` names for that
/// number, else the main display. Desktops are never removed and windows never move.
@MainActor
final class NativeDesktopTopUp {
    var create: (String) -> UInt64? = { NativeSpaceCreator.create(onDisplay: $0) }
    var isAvailable: () -> Bool = { NativeSpaceCreator.isAvailable }
    var now: () -> ContinuousClock.Instant = { .now }
    /// A display arriving or leaving reports passing topologies; wait for them to settle.
    var settleDelay: Duration = .seconds(1)
    var confirmTimeout: Duration = .seconds(2)
    private(set) var status = "not run"
    private var pending: (spaceID: String, number: Int, since: ContinuousClock.Instant)?
    private(set) var lastConfirmedCreation: Int?
    private var displaysKey: [String] = []
    private var displaysSince: ContinuousClock.Instant?
    /// The displays and target a failed attempt saw; nothing retries until either changes.
    private var stoppedAt: String?

    /// A config reload retries what an earlier attempt gave up on.
    func reset() {
        stoppedAt = nil
        status = "not run"
    }

    /// Returns true when it changed the topology and a fresh read should follow.
    @discardableResult
    func observed(_ displays: [NativeSpaceDisplay], target: Int, home: (Int) -> String?,
                  scheduleRead: (Duration) -> Void) -> Bool {
        let key = displays.map(\.identifier).sorted()
        if key != displaysKey { displaysKey = key; displaysSince = now() }
        if let pending {
            let desktops = displays.flatMap { $0.spaces.filter(\.isDesktop) }
            if let index = desktops.firstIndex(where: { $0.id == pending.spaceID }) {
                self.pending = nil
                lastConfirmedCreation = index + 1
                status = "created desktop \(index + 1)"
            } else if pending.since.duration(to: now()) < confirmTimeout {
                scheduleRead(confirmTimeout - pending.since.duration(to: now()))
                return false
            } else {
                self.pending = nil
                return stop("desktop \(pending.number) did not appear", key, target)
            }
        }
        guard let step = NativeDesktopTopUpPlan.next(displays, target: target, home: home) else {
            if target > 0, stoppedAt == nil, lastConfirmedCreation == nil { status = "all \(target) configured desktops present" }
            return false
        }
        guard stoppedAt != stopKey(key, target) else { return false }
        if let since = displaysSince, since.duration(to: now()) < settleDelay {
            scheduleRead(settleDelay - since.duration(to: now()))
            return false
        }
        guard isAvailable() else { return stop("desktop creation is unavailable on this macOS", key, target) }
        guard let spaceID = create(step.display) else {
            return stop("could not create desktop \(step.number)", key, target)
        }
        pending = (String(spaceID), step.number, now())
        status = "creating desktop \(step.number)"
        scheduleRead(confirmTimeout)
        print("WinMuxX: requested native desktop \(step.number) (Space \(spaceID)) on \(step.display)")
        return true
    }

    private func stopKey(_ displays: [String], _ target: Int) -> String { "\(target)|\(displays.joined(separator: ","))" }

    private func stop(_ reason: String, _ displays: [String], _ target: Int) -> Bool {
        stoppedAt = stopKey(displays, target)
        status = "stopped: \(reason)"
        print("WinMuxX: native desktop top-up stopped: \(reason)")
        return false
    }
}

/// The display a configured desktop number belongs on.
@MainActor
func nativeDesktopHome(_ number: Int) -> String? {
    (resolvedForceAssignedMonitor(forWorkspaceName: String(number)) ?? mainMonitor).displayUUID
}
