import Foundation

enum OriginalWindowRestoreError: Error { case unavailable, rejected }

/// Successful restoration is performed once per enabled interval. A failed retry
/// must not overwrite a window moved while management was disabled.
@MainActor
final class OriginalWindowRestoreTracker {
    private var restored = Set<RecoveryWindowIdentity>()
    private var failures: [RecoveryWindowIdentity: CGRect] = [:]
    func reset() { restored.removeAll(); failures.removeAll() }
    func forget(_ identity: RecoveryWindowIdentity) { restored.remove(identity); failures[identity] = nil }
    func succeeded(_ identity: RecoveryWindowIdentity) { restored.insert(identity); failures[identity] = nil }
    func failed(_ identity: RecoveryWindowIdentity, frame: CGRect?) {
        // Losing native bounds is not evidence of manual movement. Keep the last
        // known failure frame so a later retry can still protect an off-state move.
        if let frame { failures[identity] = frame }
    }
    func frameIsUnchanged(_ before: CGRect?, _ after: CGRect?) -> Bool {
        guard let before, let after else { return false }
        return recoveryFrameMatches(actual: after, expected: before)
    }
    func shouldRestore(_ identity: RecoveryWindowIdentity, currentFrame: CGRect?) -> Bool {
        guard !restored.contains(identity) else { return false }
        if let failedFrame = failures[identity], let currentFrame, !frameIsUnchanged(failedFrame, currentFrame) {
            succeeded(identity)
            return false
        }
        return true
    }
}
