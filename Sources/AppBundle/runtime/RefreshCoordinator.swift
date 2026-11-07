import Foundation
import Common

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
