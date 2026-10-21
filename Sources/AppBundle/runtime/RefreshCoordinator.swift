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
    var pendingActivation: RefreshActivationContext?
    var pendingRefreshRequest: (event: RefreshSessionEvent, optimisticallyPreLayoutWorkspaces: Bool)? = nil

    func invalidate() {
        activeScheduledRefreshGeneration &+= 1
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeScheduledRefreshEvent = nil
        pendingRefreshRequest = nil
        pendingActivation = nil
    }
}
