@testable import AppBundle
import XCTest

private actor RetryGate {
    private var continuation: CheckedContinuation<Void, any Error>?
    let started: @Sendable () -> Void
    init(started: @escaping @Sendable () -> Void) { self.started = started }
    func sleep(_ delay: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation = $0; started() }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
final class AppRegistrationRetriesTest: XCTestCase {
    func testRetryRunsWithoutAnotherEventAndSuccessClearsBackoff() async {
        let started = expectation(description: "Retry timer installed")
        let retried = expectation(description: "Registration retried")
        let gate = RetryGate { started.fulfill() }
        var now = 0.0
        let retries = AppRegistrationRetries(now: { now }, sleep: { try await gate.sleep($0) })
        defer { retries.cancelAll() }
        let process = RegistrationProcess(pid: 1, launchDate: Date(timeIntervalSince1970: 1))
        let task = retries.failed(process) { retried.fulfill() }
        XCTAssertFalse(retries.canAttempt(process))
        await fulfillment(of: [started], timeout: 2)
        now = 1
        await gate.release()
        await fulfillment(of: [retried], timeout: 2)
        await task?.value
        retries.cancel(pid: 1)
        XCTAssertTrue(retries.canAttempt(process))
    }

    func testPidReuseCancelsAnOlderLaunchRetry() async {
        let started = expectation(description: "Old timer installed")
        let gate = RetryGate { started.fulfill() }
        let retries = AppRegistrationRetries(sleep: { try await gate.sleep($0) })
        defer { retries.cancelAll() }
        let old = RegistrationProcess(pid: 2, launchDate: Date(timeIntervalSince1970: 1))
        let new = RegistrationProcess(pid: 2, launchDate: Date(timeIntervalSince1970: 2))
        var called = false
        let task = retries.failed(old) { called = true }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(retries.canAttempt(new))
        await gate.release()
        await task?.value
        XCTAssertFalse(called)
    }

    func testBackoffIsBoundedAndOnlyFiveAutomaticRetriesAreScheduled() {
        var now = 0.0
        let retries = AppRegistrationRetries(now: { now })
        defer { retries.cancelAll() }
        let process = RegistrationProcess(pid: 3, launchDate: Date())
        for (index, delay) in [1.0, 2, 4, 8, 16, 30, 30].enumerated() {
            let start = now
            let task = retries.failed(process) { XCTFail("Test timers must be cancelled") }
            XCTAssertEqual(task != nil, index < 5)
            XCTAssertFalse(retries.canAttempt(process))
            now = start + delay - 0.001
            XCTAssertFalse(retries.canAttempt(process))
            now = start + delay
            XCTAssertTrue(retries.canAttempt(process))
        }
    }
}
