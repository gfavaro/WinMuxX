@testable import AppBundle
import AppKit
import Common
import XCTest

final class RefreshFailureRecoveryTest: XCTestCase {
    @MainActor
    func testQueriesDoNotReconcileLayoutPublishUIOrScheduleRefresh() async throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        TrayMenuModel.shared.isEnabled = true
        let window = TestWindow.new(id: 800, parent: focus.workspace.rootTilingContainer)
        let untouched = Workspace.get(byName: "unreconciled-empty")
        var refreshes = 0
        setScheduledRefreshOverrideForTests { _, _ in refreshes += 1 }
        let command = ListModesCommand(args: ListModesCmdArgs(rawArgs: []))
        for _ in 0..<100 {
            _ = try await runCommandSession(.socketServer(command.args), .forceRun,
                isQuery: command.isQuery, shouldSchedulePostRefresh: !command.canSkipPostCommandRefresh) {
                try await command.run(.defaultEnv, .emptyStdin)
            }
        }
        XCTAssertTrue(Workspace.existing(byName: untouched.name) === untouched)
        XCTAssertNil(window.lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(refreshes, 0)
    }

    func testCancelledAXJobSkipsAttributeAndWindowIdRequests() {
        let job = RunLoopJob()
        job.cancel()
        let element = AXUIElementCreateApplication(getpid())
        RunLoopJob.$current.withValue(job) {
            switch element.read(Ax.titleAttr) {
                case .success: XCTFail("Cancelled job performed a read")
                case .failure(let error): XCTAssertEqual(error.code, .cannotComplete)
            }
            XCTAssertEqual(element.containingWindowIdWithError().error, .cannotComplete)
            XCTAssertNil(element.containingWindowId())
        }
    }

    func testConcurrentCancellationIsIdempotentAndVisible() {
        let job = RunLoopJob()
        XCTAssertFalse(job.isCancelled)
        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            job.cancel()
            XCTAssertTrue(job.isCancelled)
        }
        XCTAssertThrowsError(try job.checkCancellation())
    }

    @MainActor
    func testThrowingLightSessionDrainsInterruptedCreationRefresh() async throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        TrayMenuModel.shared.isEnabled = true
        let started = expectation(description: "creation started")
        let recovered = expectation(description: "creation resumed")
        var calls = 0
        setScheduledRefreshOverrideForTests { _, _ in
            calls += 1
            if calls == 1 {
                started.fulfill()
                try await Task.sleep(for: .seconds(10))
            } else { recovered.fulfill() }
        }
        scheduleRefreshSession(.ax(kAXWindowCreatedNotification as String))
        await fulfillment(of: [started], timeout: 2)
        enum ProbeFailure: Error { case failed }
        do {
            try await runLightSession(.hotkeyBinding, .forceRun, shouldSchedulePostRefresh: false) {
                throw ProbeFailure.failed
            }
            XCTFail("Expected failure")
        } catch ProbeFailure.failed {}
        await fulfillment(of: [recovered], timeout: 2)
        try await waitForScheduledRefreshForTests()
        XCTAssertEqual(calls, 2)
    }
}
