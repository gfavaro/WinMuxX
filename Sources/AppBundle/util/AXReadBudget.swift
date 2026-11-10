import AppKit
import Common
import Foundation

struct AXReadFailure: Error, LocalizedError, Sendable {
    let code: AXError
    var errorDescription: String? { "Accessibility read failed (AXError \(code.rawValue))" }
}

/// Shared by one refresh and its app-thread jobs, never reused by the next refresh.
final class AXReadBudget: @unchecked Sendable {
    @TaskLocal static var current: AXReadBudget?
    private let lock = NSLock()
    private var unavailable = Set<Int32>()

    func read<T>(pid: Int32, _ operation: () -> Result<T, AXReadFailure>) -> Result<T, AXReadFailure> {
        guard permits(pid) else { return .failure(AXReadFailure(code: .cannotComplete)) }
        let result = operation()
        if case .failure(let error) = result { record(error.code, pid: pid) }
        return result
    }

    func permits(_ pid: Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !unavailable.contains(pid)
    }

    func record(_ error: AXError, pid: Int32) {
        guard error == .cannotComplete else { return }
        lock.lock(); defer { lock.unlock() }
        unavailable.insert(pid)
    }
}

/// Runs one window's or one app's step of a session. An app that does not answer loses that
/// step, and the next refresh tries it again; every other app's windows are still handled.
@MainActor @discardableResult
func skippingUnansweredApp(_ step: @MainActor () async throws -> Void) async throws -> Bool {
    do {
        try await step()
        return true
    } catch let failure as AXReadFailure where failure.code == .cannotComplete {
        // A cancelled session's reads fail the same way: that is the session ending, not a busy app.
        try checkCancellation()
        return false
    }
}

struct NativeFocusUnknown: Error {}

@MainActor
func observeNativeFocusForSession() async throws -> (window: Window?, known: Bool) {
    do { return (try await getNativeFocusedWindow(), true) }
    catch is NativeFocusUnknown { return (nil, false) }
    catch let failure as AXReadFailure where failure.code == .cannotComplete {
        // The app said which window has focus, then stopped answering while it was registered.
        try checkCancellation()
        return (nil, false)
    }
}
