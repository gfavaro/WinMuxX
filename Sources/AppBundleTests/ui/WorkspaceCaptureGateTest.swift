@testable import AppBundle
import XCTest

private actor HeldNativeScreenshot {
    var active = 0
    var maximumActive = 0
    var requested: [Int] = []
    var held: [Int: CheckedContinuation<Int, Never>] = [:]
    func capture(_ id: Int, started: XCTestExpectation) async -> Int {
        active += 1; maximumActive = max(active, maximumActive); requested.append(id)
        let result = await withCheckedContinuation { held[id] = $0; started.fulfill() }
        active -= 1
        return result
    }
    func finish(_ id: Int) { held.removeValue(forKey: id)?.resume(returning: id) }
    func cleanUp() { let all = held; held.removeAll(); for (id, continuation) in all { continuation.resume(returning: id) } }
}

@MainActor private final class CaptureOutcome<T> { var value: Result<T, Error>? }

@MainActor
final class WorkspaceCaptureGateTest: XCTestCase {
    private func result<T: Sendable>(of task: Task<T, Error>) async -> Result<T, Error>? {
        let completed = expectation(description: "Capture task completes")
        let outcome = CaptureOutcome<T>()
        Task { outcome.value = await task.result; completed.fulfill() }
        await fulfillment(of: [completed], timeout: 2)
        return outcome.value
    }

    func testCancellationDoesNotReleaseSlotUntilNativeWorkReturns() async {
        let queued = expectation(description: "Second capture queues")
        let firstStarted = expectation(description: "First native capture")
        let secondStarted = expectation(description: "Second native capture")
        let gate = WorkspaceCaptureGate(onQueued: { queued.fulfill() })
        let native = HeldNativeScreenshot()
        addTeardownBlock { await native.cleanUp() }
        let first = Task { try await gate.run { await native.capture(1, started: firstStarted) } }
        await fulfillment(of: [firstStarted], timeout: 2)
        let second = Task { try await gate.run { await native.capture(2, started: secondStarted) } }
        await fulfillment(of: [queued], timeout: 2)
        first.cancel()
        let active = await native.active
        XCTAssertEqual(active, 1)
        await native.finish(1)
        await fulfillment(of: [secondStarted], timeout: 2)
        await native.finish(2)
        if case .some(.failure(let error)) = await result(of: first) { XCTAssertTrue(error is CancellationError) }
        else { XCTFail("Cancelled capture must not publish") }
        do { let value = try await result(of: second)?.get(); XCTAssertEqual(value, 2) } catch { XCTFail("Unexpected error: \(error)") }
        let peak = await native.maximumActive
        XCTAssertEqual(peak, 1, "Suspending native capture must not permit actor reentrancy to overlap screenshots")
    }

    func testCancelledQueuedRequestNeverStartsNativeWorkAndReleasesSlot() async {
        let queued = expectation(description: "Request waits for native slot")
        let started = expectation(description: "First screenshot")
        let never = XCTestExpectation(description: "Cancelled work must not start")
        let gate = WorkspaceCaptureGate(onQueued: { queued.fulfill() })
        let native = HeldNativeScreenshot()
        addTeardownBlock { await native.cleanUp() }
        let first = Task { try await gate.run { await native.capture(1, started: started) } }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { try await gate.run { await native.capture(2, started: never) } }
        await fulfillment(of: [queued], timeout: 2)
        second.cancel(); await native.finish(1)
        let cancelled = await result(of: second)
        await native.cleanUp()
        _ = await result(of: first)
        if case .some(.failure(let error)) = cancelled { XCTAssertTrue(error is CancellationError) }
        else { XCTFail("Expected cancellation") }
        let third = Task { try await gate.run { 3 } }
        do { let next = try await result(of: third)?.get(); XCTAssertEqual(next, 3) } catch { XCTFail("Slot was not released: \(error)") }
        let requested = await native.requested
        XCTAssertEqual(requested, [1])
    }
}
