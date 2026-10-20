/// Disable and quit may arrive together. Share the active restore, but allow a
/// later explicit disable to retry failures without retaining a completed task.
@MainActor
final class WindowRestoreCoordinator {
    private var task: Task<[RecoveryWindowIdentity], Never>?
    var isRunning: Bool { task != nil }

    func run(_ restore: @escaping @MainActor () async -> [RecoveryWindowIdentity]) async -> [RecoveryWindowIdentity] {
        if let task { return await task.value }
        let task = Task { await restore() }
        self.task = task
        let failures = await task.value
        self.task = nil
        return failures
    }
}
