import Common
import Foundation

@MainActor
final class DetectionCommit {
    let window: Window
    private let isCurrent: @MainActor (Window) -> Bool
    init(_ window: Window, isCurrent: @escaping @MainActor (Window) -> Bool) { self.window = window; self.isCurrent = isCurrent }
    func check() throws {
        try checkCancellation()
        guard isCurrent(window),
              (window.app as? MacApp)?.nsApp.isTerminated != true else { throw CancellationError() }
    }
}

@MainActor
final class WindowDetectionOperations {
    static let shared = WindowDetectionOperations()
    @TaskLocal static var current: DetectionCommit?
    private struct Operation {
        let id: UUID
        let window: Window
        let task: Task<Void, any Error>
    }
    private var operations: [UInt32: Operation] = [:]
    private var popupChecks: [UInt32: (window: Window, tasks: [Task<Void, Never>])] = [:]

    private let isCurrent: @MainActor (Window) -> Bool
    private let sleep: @Sendable (Duration) async throws -> Void
    private let requestRefresh: @MainActor () -> Void

    init(isCurrent: @escaping @MainActor (Window) -> Bool = { Window.get(byId: $0.windowId) === $0 },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         requestRefresh: @escaping @MainActor () -> Void = { scheduleRefreshSession(.globalObserver("popupRecheck")) }) {
        self.isCurrent = isCurrent; self.sleep = sleep; self.requestRefresh = requestRefresh
    }

    func run(_ window: Window, body: @escaping @MainActor () async throws -> Void) async throws {
        if let current = operations[window.windowId], current.window === window {
            // A committed callback must not join itself or form a cycle with another callback.
            // The existing owner will finish this work; ordinary refresh callers still join it.
            if Self.current != nil { return }
            return try await current.task.value
        }
        let id = UUID()
        let commit = DetectionCommit(window, isCurrent: isCurrent)
        let task = Task { @MainActor in
            try await Self.$current.withValue(commit) {
                try commit.check()
                try await body()
            }
        }
        operations[window.windowId] = Operation(id: id, window: window, task: task)
        defer { if operations[window.windowId]?.id == id { operations.removeValue(forKey: window.windowId) } }
        try await task.value
    }

    @discardableResult
    func schedulePopupChecks(_ window: Window) -> [Task<Void, Never>] {
        if let existing = popupChecks[window.windowId], existing.window === window { return existing.tasks }
        popupChecks.removeValue(forKey: window.windowId)?.tasks.forEach { $0.cancel() }
        let sleep = sleep
        let tasks = [1, 3].map { seconds in
            Task { @MainActor [weak self, weak window] in
                do { try await sleep(.seconds(seconds)) } catch { return }
                guard !Task.isCancelled, let self, let window else { return }
                if seconds == 3 { self.popupChecks.removeValue(forKey: window.windowId) }
                guard self.isCurrent(window), window.parent is MacosPopupWindowsContainer else { return }
                self.requestRefresh()
            }
        }
        popupChecks[window.windowId] = (window, tasks)
        return tasks
    }

    func resolvedPopup(_ window: Window) {
        if popupChecks[window.windowId]?.window === window {
            popupChecks.removeValue(forKey: window.windowId)?.tasks.forEach { $0.cancel() }
        }
    }

    func cancel(_ window: Window) {
        if operations[window.windowId]?.window === window { operations.removeValue(forKey: window.windowId)?.task.cancel() }
        resolvedPopup(window)
    }
    func cancel(pid: Int32) {
        for operation in Array(operations.values) where operation.window.app.pid == pid { cancel(operation.window) }
        for checks in Array(popupChecks.values) where checks.window.app.pid == pid { resolvedPopup(checks.window) }
    }
    func cancelAll() {
        operations.values.forEach { $0.task.cancel() }; operations.removeAll()
        popupChecks.values.forEach { $0.tasks.forEach { $0.cancel() } }; popupChecks.removeAll()
    }
}
