import ApplicationServices
import Common
import Foundation

/// A scheduled refresh session in flight, with the event it runs for. The two come and go together.
struct ActiveRefresh {
    let task: Task<(), any Error>
    let event: RefreshSessionEvent
}

/// Work a follow-up refresh session owes: the most demanding event of those that arrived while
/// another session ran, or that a light session interrupted.
struct RefreshRequest {
    var event: RefreshSessionEvent
    var optimisticallyPreLayoutWorkspaces: Bool
}

@MainActor
final class RefreshCoordinator {
    /// The scheduled session running now, if any. A queued follow-up is separate: a light session
    /// can interrupt the running one and leave its work owed with nothing running.
    var active: ActiveRefresh? = nil
    var activeRefreshTask: Task<(), any Error>? { active?.task }
    var activeScheduledRefreshEvent: RefreshSessionEvent? { active?.event }
    /// Advances whenever a session starts or is taken over, so a superseded session's completion
    /// knows it no longer owns what comes next.
    var activeScheduledRefreshGeneration: UInt64 = 0
    var scheduledRefreshOverrideForTests: (@MainActor @Sendable (RefreshSessionEvent, Bool) async throws -> Void)? = nil
    var refreshOverrideForTests: (@MainActor @Sendable () async throws -> Void)? = nil
    var normalizeLayoutReasonOverrideForTests: (@MainActor @Sendable () async throws -> Void)? = nil
    var activationGeneration: UInt64 = 0
    /// Advances whenever the focused workspace changes, by any path, so an activation is never
    /// attributed to a workspace the user left and returned to while AX was slow.
    var workspaceSelectionGeneration: UInt64 = 0
    var pendingActivation: RefreshActivationContext?
    /// An app activated before WinMux knew any window of it, as when it launches. Focus is not
    /// taken back from it until a window of it is focused or another app is activated.
    var windowlessActivationPid: pid_t?
    var pendingRefreshRequest: RefreshRequest? = nil

    /// What scheduling an event does: nothing, joins the owed follow-up, or starts a session.
    enum Admission {
        case dropped
        case coalesced
        case start(RefreshSessionEvent, optimisticallyPreLayoutWorkspaces: Bool, generation: UInt64)
    }

    /// Decides what a newly scheduled event does. A running session is never cancelled for it:
    /// during event bursts cancel-and-restart kept the refresh from ever completing, so later
    /// events join one follow-up that runs when the active session finishes.
    func admit(_ event: RefreshSessionEvent, optimisticallyPreLayoutWorkspaces: Bool) -> Admission {
        if Self.shouldDrop(event, activeEvent: activeScheduledRefreshEvent) ||
            Self.shouldDrop(event, activeEvent: pendingRefreshRequest?.event)
        {
            return .dropped
        }
        queueFollowUp(event, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
        if activeRefreshTask != nil { return .coalesced }
        // A light session may cancel the active task while leaving a heavier request pending.
        let request = pendingRefreshRequest!
        pendingRefreshRequest = nil
        activeScheduledRefreshGeneration += 1
        return .start(request.event, optimisticallyPreLayoutWorkspaces: request.optimisticallyPreLayoutWorkspaces,
                      generation: activeScheduledRefreshGeneration)
    }

    /// A scheduled session ended. If nobody took over meanwhile (a light session, test setup), it
    /// hands back the follow-up owed; otherwise the new owner is responsible for the next refresh.
    func finishScheduled(generation: UInt64) -> RefreshRequest? {
        guard activeScheduledRefreshGeneration == generation else { return nil }
        active = nil
        defer { pendingRefreshRequest = nil }
        return pendingRefreshRequest
    }

    /// A light session takes priority: work a native event already requested is kept as owed,
    /// and the running session is stopped so its completion can't start a follow-up mid-session.
    func beginLight() -> UInt64 {
        if let event = activeScheduledRefreshEvent {
            queueFollowUp(event, optimisticallyPreLayoutWorkspaces: false)
        }
        stopActive()
        return activeScheduledRefreshGeneration
    }

    /// A light session ended, even by error or cancellation: the owed work still has to run,
    /// unless a newer session owns the next refresh.
    func owedAfterLight(generation: UInt64) -> RefreshRequest? {
        guard activeScheduledRefreshGeneration == generation, activeRefreshTask == nil else { return nil }
        return pendingRefreshRequest
    }

    /// Adds an event to the follow-up owed, keeping the most demanding of them.
    func queueFollowUp(_ event: RefreshSessionEvent, optimisticallyPreLayoutWorkspaces: Bool) {
        pendingRefreshRequest = pendingRefreshRequest.map {
            RefreshRequest(event: Self.merge($0.event, event),
                           optimisticallyPreLayoutWorkspaces: $0.optimisticallyPreLayoutWorkspaces || optimisticallyPreLayoutWorkspaces)
        } ?? RefreshRequest(event: event, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
    }

    private static func isAxGeometry(_ event: RefreshSessionEvent) -> Bool {
        guard case .ax(let notif) = event else { return false }
        return notif == kAXMovedNotification as String || notif == kAXResizedNotification as String
    }

    /// A move or resize adds nothing while a geometry or mouse-reset session already covers it.
    static func shouldDrop(_ newEvent: RefreshSessionEvent, activeEvent: RefreshSessionEvent?) -> Bool {
        guard isAxGeometry(newEvent), let activeEvent else { return false }
        if isAxGeometry(activeEvent) { return true }
        if case .resetManipulatedWithMouse = activeEvent { return true }
        return false
    }

    /// When two refresh requests coalesce, keep the event whose session does more work, so the
    /// follow-up session covers the requirements of every event that arrived while one was running.
    static func merge(_ old: RefreshSessionEvent, _ new: RefreshSessionEvent) -> RefreshSessionEvent {
        // Parking repair is a placement-only pass. Never let it replace a pending
        // focus/tab/activation reconciliation, including one with the same cost score.
        if case .onWindowParkingDrift = new { return old }
        if case .onWindowParkingDrift = old { return new }
        func score(_ e: RefreshSessionEvent) -> Int {
            // Re-parking hidden windows after a wake has no other trigger, and it used to tie
            // with (and lose to) the Space and mouse events that arrive right after a wake.
            // From WinMux PR #30 by Ilya Kudravets.
            (e.requiresHiddenWindowsReassertion ? 4 : 0) +
                (e.requiresWindowRefreshBarrier ? 2 : 0) + (e.canReuseLastAppliedWindowFrames ? 0 : 1)
        }
        return score(new) >= score(old) ? new : old
    }

    /// Cancels the running session and takes ownership away from it: its completion no longer
    /// drains the follow-up.
    func stopActive() {
        activeScheduledRefreshGeneration &+= 1
        active?.task.cancel()
        active = nil
    }

    func invalidate() {
        stopActive()
        pendingRefreshRequest = nil
        pendingActivation = nil
        windowlessActivationPid = nil
    }
}
