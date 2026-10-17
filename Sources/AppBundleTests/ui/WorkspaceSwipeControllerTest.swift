@testable import AppBundle
import AppKit
import XCTest

@MainActor
private final class SwipePreviewSpy: WorkspaceSwipePreviewing {
    var isActive = false
    var isSettling = false
    var capturesAvailable = true
    var reveals = 0
    var cancels = 0
    var releases: [Bool] = []
    var validity: (@MainActor () -> Bool)?

    func begin(on monitor: Monitor, target: Workspace, slidesLeft: Bool,
               isValid: @escaping @MainActor () -> Bool) {
        validity = isValid
        isActive = capturesAvailable
    }
    func update(_ progress: Double) {}
    func settle(commit: Bool) { releases.append(commit) }
    func revealWorkspace() { reveals += 1; isActive = false }
    func cancel() { cancels += 1; isActive = false; validity = nil }
    func invalidate() { cancel() }
}

/// Holds navigation at the session boundary, including when its task is cancelled.
/// Tests can model native work that returns after reset without relying on delays.
@MainActor
private final class SwipeNavigationGate {
    var started: XCTestExpectation?
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var nextID = 0
    var fail = false

    func run(_ activate: @escaping @MainActor () -> Bool) async throws -> Bool {
        let id = nextID
        nextID += 1
        await withCheckedContinuation { continuation in
            continuations[id] = continuation
            started?.fulfill()
        }
        if fail { throw CocoaError(.userCancelled) }
        return activate()
    }

    func release(_ id: Int) { continuations.removeValue(forKey: id)?.resume() }
    func cleanUp() {
        let waiting = continuations.values
        continuations.removeAll()
        for continuation in waiting { continuation.resume() }
    }
}

@MainActor
final class WorkspaceSwipeControllerTest: XCTestCase {
    private var world: WorkspaceNavigationFixture!
    private var preview: SwipePreviewSpy!
    private var gate: SwipeNavigationGate!
    private var controller: WorkspaceSwipeController!
    private var failures = 0
    private var navigationAllowed = true

    override func setUp() async throws {
        world = WorkspaceNavigationFixture()
        world.spaces[2].seedMonitorIfNeeded(world.displays[0])
        world.spaces[3].seedMonitorIfNeeded(world.displays[0])
        preview = SwipePreviewSpy()
        gate = SwipeNavigationGate()
        failures = 0
        navigationAllowed = true
        controller = WorkspaceSwipeController(dependencies: WorkspaceSwipeDependencies(
            preview: preview, monitors: { [unowned self] in self.world.displays },
            pointer: { CGPoint(x: 100, y: 100) },
            canNavigate: { [unowned self] in self.navigationAllowed }, reversed: { false },
            navigate: { [gate] activate in try await gate!.run(activate) },
            navigationFailed: { [unowned self] _ in self.failures += 1 }))
    }

    override func tearDown() async throws {
        controller.reset()
        gate.cleanUp()
        controller = nil
        preview = nil
        gate = nil
        world.cleanUp()
        world = nil
    }

    private func frame(_ x: Double, fingers: Int = 3, time: Double) {
        controller.handle(WorkspaceTouchFrame(device: 1, fingers: fingers, x: x, y: 0.5,
                                              timestamp: time, contacts: 123))
    }

    private func begin(time: Double = 1) {
        frame(0.5, fingers: 0, time: time)
        frame(0.5, time: time + 0.1)
        frame(0.3, time: time + 0.2)
    }

    private func commit(time: Double = 1) async throws -> Task<Void, Never> {
        let started = expectation(description: "Navigation entered session")
        gate.started = started
        frame(0.3, fingers: 0, time: time + 0.3)
        let task = try XCTUnwrap(controller.pending)
        await fulfillment(of: [started], timeout: 2)
        gate.started = nil
        return task
    }

    private func finish(_ task: Task<Void, Never>, id: Int = 0) async {
        let completed = expectation(description: "Controller finished navigation")
        let observer = Task { await task.value; completed.fulfill() }
        defer { observer.cancel() }
        gate.release(id)
        await fulfillment(of: [completed], timeout: 2)
    }

    func testResetDuringNavigationCannotActivateOrRevealOldWorkspace() async throws {
        begin()
        let task = try await commit()
        controller.reset()
        let cancellations = preview.cancels
        await finish(task)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
        XCTAssertEqual(preview.reveals, 0)
        XCTAssertEqual(preview.cancels, cancellations)
        XCTAssertNil(controller.pending)
    }

    func testOldCompletionCannotCancelNewGestureOrClearItsNavigation() async throws {
        begin()
        let old = try await commit()
        controller.reset()
        begin(time: 3)
        let current = try await commit(time: 3)
        let cancellations = preview.cancels
        await finish(old)
        XCTAssertTrue(preview.isActive)
        XCTAssertNotNil(controller.pending)
        XCTAssertEqual(preview.cancels, cancellations)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
        await finish(current, id: 1)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[2])
        XCTAssertEqual(preview.reveals, 1)
        XCTAssertEqual(world.displays[1].activeWorkspace, world.spaces[1])
        XCTAssertEqual(world.displays[2].activeWorkspace, world.spaces[4])
    }

    func testOldFailureCannotCancelNewPreviewOrScheduleRecovery() async throws {
        begin()
        let old = try await commit()
        controller.reset()
        begin(time: 3)
        gate.fail = true
        let cancellations = preview.cancels
        await finish(old)
        XCTAssertTrue(preview.isActive)
        XCTAssertEqual(preview.cancels, cancellations)
        XCTAssertEqual(failures, 0)
    }

    func testSourceSwitchDuringGestureRejectsRelease() {
        begin()
        XCTAssertTrue(activateWorkspaceForUser(world.spaces[3], on: world.displays[0]))
        XCTAssertTrue(preview.validity?() == false)
        frame(0.3, fingers: 0, time: 1.3)
        XCTAssertNil(controller.pending)
        XCTAssertEqual(preview.releases, [false])
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[3])
    }

    func testOwnershipChangeDuringGestureRejectsRelease() {
        begin()
        XCTAssertTrue(preview.validity?() == true)
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(world.spaces[2], targetMonitor: world.displays[1]))
        XCTAssertTrue(preview.validity?() == false)
        frame(0.3, fingers: 0, time: 1.3)
        XCTAssertNil(controller.pending)
        XCTAssertEqual(preview.releases, [false])
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
    }

    func testOwnershipChangeWhileNavigationWaitsIsRevalidated() async throws {
        begin()
        let task = try await commit()
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(world.spaces[2], targetMonitor: world.displays[1]))
        await finish(task)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
        XCTAssertEqual(world.displays[1].activeWorkspace, world.spaces[2])
        XCTAssertEqual(preview.reveals, 0)
    }

    func testRuntimeBecomingUnavailableDuringGestureCancelsPreview() {
        begin()
        navigationAllowed = false
        frame(0.25, time: 1.25)
        frame(0.25, fingers: 0, time: 1.3)
        XCTAssertFalse(preview.isActive)
        XCTAssertNil(controller.pending)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
    }

    func testRuntimeBecomingUnavailableDuringNavigationRejectsActivation() async throws {
        begin()
        let task = try await commit()
        navigationAllowed = false
        await finish(task)
        XCTAssertFalse(preview.isActive)
        XCTAssertEqual(preview.reveals, 0)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
    }

    func testMissingCaptureDoesNotBlockNavigation() async throws {
        preview.capturesAvailable = false
        begin()
        XCTAssertFalse(preview.isActive)
        let task = try await commit()
        await finish(task)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[2])
        XCTAssertEqual(preview.releases, [true])
        XCTAssertEqual(failures, 0)
    }

    func testNavigationFailureCancelsPreviewAndReportsRecovery() async throws {
        gate.fail = true
        begin()
        let task = try await commit()
        await finish(task)
        XCTAssertFalse(preview.isActive)
        XCTAssertEqual(preview.reveals, 0)
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
    }
}
