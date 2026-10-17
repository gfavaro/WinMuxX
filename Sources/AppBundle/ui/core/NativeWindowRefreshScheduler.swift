import Foundation

/// Native notifications can describe many transactions for one visual change.
/// A finite pending task bounds scans without keeping an idle clock running.
@MainActor
final class NativeWindowRefreshScheduler {
    private var pending: Task<Void, Never>?
    private let sleep: @Sendable () async throws -> Void

    init(sleep: @escaping @Sendable () async throws -> Void = {
        try await Task.sleep(for: .milliseconds(16))
    }) { self.sleep = sleep }

    func request(_ action: @escaping @MainActor () -> Void) {
        guard pending == nil else { return }
        pending = Task { @MainActor [weak self, sleep] in
            do { try await sleep() } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            action()
        }
    }

    func cancel() { pending?.cancel(); pending = nil }
    isolated deinit { pending?.cancel() }
}
