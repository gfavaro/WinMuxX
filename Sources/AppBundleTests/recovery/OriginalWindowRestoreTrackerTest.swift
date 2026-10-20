@testable import AppBundle
import Foundation
import XCTest

@MainActor
final class OriginalWindowRestoreTrackerTest: XCTestCase {
    private let identity = RecoveryWindowIdentity(windowId: 10, pid: 20, bundleId: "test.editor",
        applicationLaunchDate: Date(timeIntervalSince1970: 100))
    private let frame = CGRect(x: 100, y: 200, width: 800, height: 600)

    func testSuccessfulRestoreDoesNotRepeatUntilManagementResumes() {
        let tracker = OriginalWindowRestoreTracker()
        XCTAssertTrue(tracker.shouldRestore(identity, currentFrame: frame))
        tracker.succeeded(identity)
        XCTAssertFalse(tracker.shouldRestore(identity, currentFrame: frame.offsetBy(dx: 50, dy: 0)))
        tracker.reset()
        XCTAssertTrue(tracker.shouldRestore(identity, currentFrame: frame))
    }

    func testFailedRestoreRetriesButPreservesManualMovementWhileDisabled() {
        let tracker = OriginalWindowRestoreTracker()
        tracker.failed(identity, frame: frame)
        XCTAssertTrue(tracker.shouldRestore(identity, currentFrame: frame))
        XCTAssertFalse(tracker.shouldRestore(identity, currentFrame: frame.offsetBy(dx: 20, dy: 0)))
        XCTAssertFalse(tracker.shouldRestore(identity, currentFrame: frame))
    }

    func testUnknownGeometryNeverPassesTheBeforeWriteGuard() {
        let tracker = OriginalWindowRestoreTracker()
        XCTAssertFalse(tracker.frameIsUnchanged(nil, frame))
        XCTAssertFalse(tracker.frameIsUnchanged(frame, nil))
        XCTAssertFalse(tracker.frameIsUnchanged(frame, frame.offsetBy(dx: 3, dy: 0)))
        XCTAssertTrue(tracker.frameIsUnchanged(frame, frame.offsetBy(dx: 1, dy: 0)))
    }

    func testMissingBoundsKeepTheFailureAndLastKnownMovementBaseline() {
        let tracker = OriginalWindowRestoreTracker()
        tracker.failed(identity, frame: frame)
        XCTAssertTrue(tracker.shouldRestore(identity, currentFrame: nil))
        tracker.failed(identity, frame: nil)
        XCTAssertTrue(tracker.shouldRestore(identity, currentFrame: frame))
        XCTAssertFalse(tracker.shouldRestore(identity, currentFrame: frame.offsetBy(dx: 50, dy: 0)))
    }

    func testClosedIdentityIsReleasedAndReusedIdsRemainIndependent() {
        let tracker = OriginalWindowRestoreTracker()
        tracker.succeeded(identity)
        let reused = RecoveryWindowIdentity(windowId: identity.windowId, pid: identity.pid,
            bundleId: identity.bundleId, applicationLaunchDate: Date(timeIntervalSince1970: 200))
        XCTAssertTrue(tracker.shouldRestore(reused, currentFrame: frame))
        tracker.forget(identity)
        XCTAssertTrue(tracker.shouldRestore(identity, currentFrame: frame))
    }
}

@MainActor
final class WindowRestoreCoordinatorTest: XCTestCase {
    func testConcurrentDisableAndQuitShareFailuresAndLaterDisableCanRetry() async {
        let coordinator = WindowRestoreCoordinator()
        let identity = RecoveryWindowIdentity(windowId: 1, pid: 2, bundleId: nil,
            applicationLaunchDate: Date(timeIntervalSince1970: 100))
        var calls = 0
        let started = expectation(description: "restore started")
        var release: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            await coordinator.run {
                calls += 1
                await withCheckedContinuation { release = $0; started.fulfill() }
                return [identity]
            }
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(coordinator.isRunning)
        let second = Task { @MainActor in await coordinator.run { calls += 1; return [] } }
        await Task.yield()
        release?.resume()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, [identity])
        XCTAssertEqual(secondResult, [identity])
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(coordinator.isRunning)
        let retry = await coordinator.run { calls += 1; return [] }
        XCTAssertTrue(retry.isEmpty)
        XCTAssertEqual(calls, 2)
    }
}
