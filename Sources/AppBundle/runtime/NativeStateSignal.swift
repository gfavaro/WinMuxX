import Foundation

/// Wakes native waiters when readiness or the observed desktops may have changed, so
/// commands resume on the change itself instead of polling for it.
@MainActor
final class NativeStateSignal {
    private var waiters: [UUID: (CheckedContinuation<Void, Never>, Task<Void, Never>)] = [:]

    func notify() {
        let woken = waiters
        waiters = [:]
        for (continuation, timer) in woken.values {
            timer.cancel()
            continuation.resume()
        }
    }

    /// Returns once `condition` holds or the timeout passes; the result is its final value.
    func wait(timeout: Duration, until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline, !Task.isCancelled {
            await nextChange(before: deadline)
        }
        return condition()
    }

    /// Returns at the next change, or at the deadline when nothing changes first.
    func nextChange(before deadline: ContinuousClock.Instant) async {
        let id = UUID()
        await withCheckedContinuation { continuation in
            let timer = Task { @MainActor [weak self] in
                try? await Task.sleep(until: deadline)
                self?.waiters.removeValue(forKey: id)?.0.resume()
            }
            waiters[id] = (continuation, timer)
        }
    }
}
