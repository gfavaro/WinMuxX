@testable import AppBundle
import XCTest

@MainActor
final class RefreshCoordinatorOwnershipTest: WorkspaceTestCase {
    func testIndependentOwnersAndLateCompletionStayIsolated() async throws {
        let first = WinMuxRuntime(), second = WinMuxRuntime()
        var continuation: CheckedContinuation<Void, Never>?
        let started = expectation(description: "old runtime task started")
        let task = first.throwingTask {
            await withCheckedContinuation { continuation = $0; started.fulfill() }
            // Deliberately ignore cancellation to model an already-running native call.
            recordRefreshActivation(workspaceName: "old", pid: 11)
        }
        first.refresh.activeRefreshTask = task
        await fulfillment(of: [started], timeout: 2)
        second.withValue { recordRefreshActivation(workspaceName: "new", pid: 22) }
        first.refresh.invalidate()
        continuation?.resume()
        try await task.value
        XCTAssertEqual(first.refresh.pendingActivation?.workspaceName, "old")
        XCTAssertEqual(second.refresh.pendingActivation?.workspaceName, "new")
        XCTAssertNil(second.refresh.activeRefreshTask)
        second.refresh.invalidate()
        XCTAssertNil(second.refresh.pendingActivation)
        XCTAssertEqual(first.refresh.pendingActivation?.workspaceName, "old")
    }

    func testTestOverridesBelongToRuntime() {
        let first = WinMuxRuntime(), second = WinMuxRuntime()
        first.withValue { setScheduledRefreshOverrideForTests { _, _ in } }
        XCTAssertNotNil(first.refresh.scheduledRefreshOverrideForTests)
        XCTAssertNil(second.refresh.scheduledRefreshOverrideForTests)
        second.withValue { setScheduledRefreshOverrideForTests(nil) }
        XCTAssertNotNil(first.refresh.scheduledRefreshOverrideForTests)
    }
}
