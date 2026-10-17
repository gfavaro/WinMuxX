@testable import AppBundle
import Common
import XCTest
import os

@MainActor
final class RecoveryEfficiencyTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws { setUpWorkspacesForTests() }

    func testTerminatedWindowAssignmentsRetainOneLeafEach() {
        let workspace = focus.workspace
        for id in 1...500 {
            let window = TestWindow.new(id: UInt32(id), parent: workspace.rootTilingContainer)
            window.restartIdentity = RestartWindowIdentity(bundleId: "test.editor", pid: 40,
                launchDate: Date(timeIntervalSince1970: 10), title: "Document \(id)")
        }
        for window in workspace.allLeafWindowsRecursive {
            rememberRestartWindowBeforeAppTermination(window)
            window.unbindFromParent()
        }
        let snapshots = runtime.recovery.pendingRestartSnapshots
        XCTAssertEqual(snapshots.count, 500)
        XCTAssertEqual(snapshots.flatMap(\.world.workspaces).reduce(0) {
            $0 + collectFrozenWindows($1).count
        }, 500)
    }

    func testConsumedTreesWaitForReadersAndThenRelease() {
        let world = snapshotCurrentFrozenWorld()
        runtime.recovery.pendingRestartSnapshots = [PendingRestartSnapshot(world: world, remainingWindowIds: [])]
        runtime.recovery.restartMatchedWindows = [[:]]
        runtime.recovery.restartRestorationsInFlight = 1
        compactPendingRestartSnapshots()
        XCTAssertEqual(runtime.recovery.pendingRestartSnapshots.count, 1)
        runtime.recovery.restartRestorationsInFlight = 0
        runtime.recovery.lateRestartTreeDeadline = .now.addingTimeInterval(30)
        compactPendingRestartSnapshots()
        XCTAssertEqual(runtime.recovery.pendingRestartSnapshots.count, 1)
        runtime.recovery.lateRestartTreeDeadline = nil
        compactPendingRestartSnapshots()
        XCTAssertTrue(runtime.recovery.pendingRestartSnapshots.isEmpty)
        XCTAssertTrue(runtime.recovery.restartMatchedWindows.isEmpty)
    }

    func testUnchangedSnapshotDoesNotRewritePrimaryOrBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let first = makeRestartEnvelope()
        XCTAssertTrue(try saveRestartEnvelope(first, to: url))
        XCTAssertFalse(try saveRestartEnvelope(makeRestartEnvelope(), to: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("backup").path))
    }

    func testWriterCoalescesBurstOffMainAndFlushPreservesNewestState() throws {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let writes = OSAllocatedUnfairLock(initialState: [(Int, Bool)]())
        let writer = RestartStateWriter { envelope, _ in
            let first = writes.withLock { values in
                values.append((envelope.version, Thread.isMainThread))
                return values.count == 1
            }
            if first { entered.signal(); release.wait() }
        }
        let world = snapshotCurrentFrozenWorld()
        let url = URL(fileURLWithPath: "/unused-test-state")
        writer.submit(.init(version: 1, world: world, pending: nil), to: url)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        for version in 2...100 {
            writer.submit(.init(version: version, world: world, pending: nil), to: url)
        }
        release.signal()
        try writer.flush()
        XCTAssertEqual(writes.withLock { $0.map(\.0) }, [1, 100])
        XCTAssertTrue(writes.withLock { $0.allSatisfy { !$0.1 } })
        try writer.flush(.init(version: 101, world: world, pending: nil), to: url)
        try writer.flush(.init(version: 101, world: world, pending: nil), to: url)
        XCTAssertEqual(writes.withLock { $0.map(\.0) }, [1, 100, 101])
    }
}
