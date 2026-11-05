import Foundation
import Common

@MainActor
final class RefreshCoordinator {
    var activeRefreshTask: Task<(), any Error>? = nil
    var activeScheduledRefreshEvent: RefreshSessionEvent? = nil
    var activeScheduledRefreshGeneration: UInt64 = 0
    var scheduledRefreshOverrideForTests: (@MainActor @Sendable (RefreshSessionEvent, Bool) async throws -> Void)? = nil
    var refreshOverrideForTests: (@MainActor @Sendable () async throws -> Void)? = nil
    var normalizeLayoutReasonOverrideForTests: (@MainActor @Sendable () async throws -> Void)? = nil
    var activationGeneration: UInt64 = 0
    /// Advances on every user workspace selection, so an activation is never attributed to a
    /// workspace the user left and returned to while AX was slow.
    var workspaceSelectionGeneration: UInt64 = 0
    var workspaceSelectionGenerationFocus: WorkspaceId?
    var pendingActivation: RefreshActivationContext?
    /// An app activated before WinMux knew any window of it, as when it launches. Focus is not
    /// taken back from it until a window of it is focused or another app is activated.
    var windowlessActivationPid: pid_t?
    var pendingRefreshRequest: (event: RefreshSessionEvent, optimisticallyPreLayoutWorkspaces: Bool)? = nil

    func invalidate() {
        activeScheduledRefreshGeneration &+= 1
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeScheduledRefreshEvent = nil
        pendingRefreshRequest = nil
        pendingActivation = nil
        windowlessActivationPid = nil
    }
}
