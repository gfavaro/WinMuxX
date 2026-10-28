import Foundation

/// Wakes waiters when the state they watch may have changed, so they resume on the change
/// itself instead of polling for it. Waiters re-check their condition after each wake.
@MainActor
final class ChangeSignal {
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

/// AX window destruction and app termination, for code waiting on a close or quit it asked for.
@MainActor let windowLifecycleChanges = ChangeSignal()
