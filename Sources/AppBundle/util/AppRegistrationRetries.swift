import Foundation

struct RegistrationProcess: Hashable, Sendable {
    let pid: Int32
    let launchDate: Date?
    let fallbackIdentity: ObjectIdentifier?
    init(pid: Int32, launchDate: Date?, fallbackIdentity: ObjectIdentifier? = nil) {
        self.pid = pid; self.launchDate = launchDate
        self.fallbackIdentity = launchDate == nil ? fallbackIdentity : nil
    }
}

@MainActor
final class AppRegistrationRetries {
    private struct Failure {
        let process: RegistrationProcess
        let attempts: Int
        let nextAttempt: TimeInterval
        var task: Task<Void, Never>?
    }
    private var failures: [Int32: Failure] = [:]
    private let now: () -> TimeInterval
    private let sleep: @Sendable (Duration) async throws -> Void

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.now = now; self.sleep = sleep
    }

    func canAttempt(_ process: RegistrationProcess) -> Bool {
        guard let failure = failures[process.pid] else { return true }
        guard failure.process == process else { cancel(pid: process.pid); return true }
        return now() >= failure.nextAttempt
    }

    @discardableResult
    func failed(_ process: RegistrationProcess, retry: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        let previous = failures[process.pid]
        previous?.task?.cancel()
        let attempts: Int
        if let previous, previous.process == process { attempts = min(previous.attempts + 1, 6) }
        else { attempts = 1 }
        let delay = [1.0, 2, 4, 8, 16, 30][attempts - 1]
        failures[process.pid] = Failure(process: process, attempts: attempts, nextAttempt: now() + delay)
        guard attempts <= 5 else { return nil }
        let sleep = sleep
        let task = Task { [weak self] in
            do { try await sleep(.seconds(delay)) } catch { return }
            guard !Task.isCancelled, let self, let current = self.failures[process.pid],
                  current.process == process, current.attempts == attempts else { return }
            self.failures[process.pid]?.task = nil
            await retry()
        }
        failures[process.pid]?.task = task
        return task
    }

    func cancel(pid: Int32) { failures.removeValue(forKey: pid)?.task?.cancel() }
    func cancelAll() {
        for failure in failures.values { failure.task?.cancel() }
        failures.removeAll()
    }
}
