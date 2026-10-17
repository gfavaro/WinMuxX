@testable import AppBundle
import Common
import XCTest

@MainActor
private final class DetectionGate {
    var continuation: CheckedContinuation<Void, Never>?
    let started: XCTestExpectation
    init(_ started: XCTestExpectation) { self.started = started }
    func wait() async { await withCheckedContinuation { continuation = $0; started.fulfill() } }
    func release() { continuation?.resume(); continuation = nil }
}

private struct DetectionProbeCommand: Command {
    let args = ListMonitorsCmdArgs(rawArgs: [])
    let operation: @MainActor @Sendable () async throws -> Bool
    var shouldResetClosedWindowsCache: Bool { false }
    @MainActor func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool { try await operation() }
}

@MainActor
final class WindowDetectionOperationsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws {
        WindowDetectionOperations.shared.cancelAll()
        setUpWorkspacesForTests()
    }

    func testCommittedCommandsFinishDespiteCallerCancellation() async {
        let coordinator = WindowDetectionOperations()
        defer { coordinator.cancelAll() }
        let window = TestWindow.new(id: 8201, parent: focus.workspace.rootTilingContainer)
        let started = expectation(description: "First command running")
        let finished = expectation(description: "Both commands finished")
        let gate = DetectionGate(started)
        defer { gate.release() }
        var effects = [Int]()
        let commands: [any Command] = [DetectionProbeCommand { effects.append(1); await gate.wait(); return true },
                                        DetectionProbeCommand { effects.append(2); return true }]
        let caller = Task {
            defer { finished.fulfill() }
            do { try await coordinator.run(window) { _ = try await commands.runCmdSeq(.defaultEnv, .emptyStdin) } }
            catch { XCTFail("Committed operation was interrupted: \(error)") }
        }
        defer { caller.cancel() }
        await fulfillment(of: [started], timeout: 2)
        caller.cancel()
        gate.release()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(effects, [1, 2])
    }

    func testDestroyedIdentityStopsRemainingCommands() async {
        let coordinator = WindowDetectionOperations()
        defer { coordinator.cancelAll() }
        let window = TestWindow.new(id: 8202, parent: focus.workspace.rootTilingContainer)
        let started = expectation(description: "First command running")
        let finished = expectation(description: "Invalidated operation stopped")
        let gate = DetectionGate(started)
        defer { gate.release() }
        var secondRan = false
        let commands: [any Command] = [DetectionProbeCommand { await gate.wait(); return true },
                                        DetectionProbeCommand { secondRan = true; return true }]
        let caller = Task {
            defer { finished.fulfill() }
            do { try await coordinator.run(window) { _ = try await commands.runCmdSeq(.defaultEnv, .emptyStdin) }; XCTFail("Expected destruction to stop the operation") }
            catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        }
        defer { caller.cancel() }
        await fulfillment(of: [started], timeout: 2)
        window.unbindFromParent()
        coordinator.cancel(window)
        gate.release()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertFalse(secondRan)
    }

    func testNestedDetectionDoesNotWaitForAnotherCommittedOperation() async {
        let coordinator = WindowDetectionOperations()
        defer { coordinator.cancelAll() }
        let firstWindow = TestWindow.new(id: 8206, parent: focus.workspace.rootTilingContainer)
        let secondWindow = TestWindow.new(id: 8207, parent: focus.workspace.rootTilingContainer)
        let started = expectation(description: "First operation running")
        let nestedReturned = expectation(description: "Nested request returned without joining")
        let drained = expectation(description: "Both operations drained")
        drained.expectedFulfillmentCount = 2
        let gate = DetectionGate(started)
        defer { gate.release() }
        let first = Task {
            defer { drained.fulfill() }
            try? await coordinator.run(firstWindow) { await gate.wait() }
        }
        defer { first.cancel() }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            defer { drained.fulfill() }
            do {
                try await coordinator.run(secondWindow) {
                    try await coordinator.run(firstWindow) { XCTFail("Duplicate detection ran") }
                    nestedReturned.fulfill()
                }
            } catch { XCTFail("Nested request failed: \(error)") }
        }
        defer { second.cancel() }
        await fulfillment(of: [nestedReturned], timeout: 2)
        gate.release()
        await fulfillment(of: [drained], timeout: 2)
    }

    func testConcurrentRequestsJoinTheSameCommittedOperation() async {
        let coordinator = WindowDetectionOperations()
        defer { coordinator.cancelAll() }
        let window = TestWindow.new(id: 8203, parent: focus.workspace.rootTilingContainer)
        let started = expectation(description: "Operation running")
        let joined = expectation(description: "Joined operation returned")
        let gate = DetectionGate(started)
        defer { gate.release() }
        let first = Task { try await coordinator.run(window) { await gate.wait() } }
        defer { first.cancel() }
        await fulfillment(of: [started], timeout: 2)
        let joining = expectation(description: "Second caller joined")
        let second = Task {
            joining.fulfill()
            do { try await coordinator.run(window) { XCTFail("Duplicate operation ran") } }
            catch { XCTFail("Join failed: \(error)") }
            joined.fulfill()
        }
        defer { second.cancel() }
        await fulfillment(of: [joining], timeout: 2)
        gate.release()
        await fulfillment(of: [joined], timeout: 2)
    }
}

private actor PopupTimerGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    let started: @Sendable () -> Void
    init(started: @escaping @Sendable () -> Void) { self.started = started }
    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { waiters.append($0); started() }
    }
    func releaseAll() { let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() } }
}

extension WindowDetectionOperationsTest {
    func testPopupRechecksAreBoundedAndDoNotNeedAnotherEvent() async {
        let window = TestWindow.new(id: 8204, parent: macosPopupWindowsContainer)
        defer { window.unbindFromParent() }
        let timers = expectation(description: "Two popup checks scheduled")
        timers.expectedFulfillmentCount = 2
        let refreshed = expectation(description: "Both checks requested refresh")
        refreshed.expectedFulfillmentCount = 2
        let gate = PopupTimerGate { timers.fulfill() }
        let coordinator = WindowDetectionOperations(isCurrent: { $0 === window }, sleep: { await gate.sleep($0) },
                                                    requestRefresh: { refreshed.fulfill() })
        defer { coordinator.cancelAll() }
        coordinator.schedulePopupChecks(window)
        coordinator.schedulePopupChecks(window) // repeated requests must coalesce
        await fulfillment(of: [timers], timeout: 2)
        await gate.releaseAll()
        await fulfillment(of: [refreshed], timeout: 2)
    }

    func testResolvedPopupCancelsBothRechecks() async {
        let window = TestWindow.new(id: 8205, parent: macosPopupWindowsContainer)
        defer { window.unbindFromParent() }
        let timers = expectation(description: "Two popup checks scheduled")
        timers.expectedFulfillmentCount = 2
        let completed = expectation(description: "Cancelled checks drained")
        let gate = PopupTimerGate { timers.fulfill() }
        let coordinator = WindowDetectionOperations(isCurrent: { $0 === window }, sleep: { await gate.sleep($0) },
                                                    requestRefresh: { XCTFail("Resolved popup requested refresh") })
        defer { coordinator.cancelAll() }
        let tasks = coordinator.schedulePopupChecks(window)
        await fulfillment(of: [timers], timeout: 2)
        coordinator.resolvedPopup(window)
        await gate.releaseAll()
        let observer = Task { for task in tasks { await task.value }; completed.fulfill() }
        defer { observer.cancel() }
        await fulfillment(of: [completed], timeout: 2)
    }
}
