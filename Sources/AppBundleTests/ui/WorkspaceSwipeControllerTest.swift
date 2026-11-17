@testable import AppBundle
import AppKit
import XCTest

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
    private var gate: SwipeNavigationGate!
    private var controller: WorkspaceSwipeController!
    private var failures = 0
    private var navigationAllowed = true
    private var keepsSwipe = false

    override func setUp() async throws {
        world = WorkspaceNavigationFixture()
        world.spaces[2].seedMonitorIfNeeded(world.displays[0])
        world.spaces[3].seedMonitorIfNeeded(world.displays[0])
        gate = SwipeNavigationGate()
        failures = 0
        navigationAllowed = true
        keepsSwipe = false
        controller = WorkspaceSwipeController(dependencies: WorkspaceSwipeDependencies(
            monitors: { [unowned self] in self.world.displays },
            pointer: { CGPoint(x: 100, y: 100) },
            canNavigate: { [unowned self] in self.navigationAllowed }, reversed: { false },
            navigate: { [gate] activate in try await gate!.run(activate) },
            navigationFailed: { [unowned self] _ in self.failures += 1 },
            keepsSwipe: { [unowned self] in self.keepsSwipe }))
    }

    override func tearDown() async throws {
        controller.reset()
        gate.cleanUp()
        controller = nil
        gate = nil
        world.cleanUp()
        world = nil
    }

    /// A macOS swipe toward the next workspace, most of the way across.
    private func begin(time: Double = 1) {
        _ = controller.beginDockSwipe(incomingFromBelow: true, progress: 0.8, timestamp: time + 0.2)
    }

    private func move(_ progress: Double, time: Double) {
        controller.updateDockSwipe(progress, timestamp: time)
    }

    private func release(time: Double) {
        controller.endDockSwipe(commit: true, timestamp: time)
    }

    private func commit(time: Double = 1) async throws -> Task<Void, Never> {
        let started = expectation(description: "Navigation entered session")
        gate.started = started
        release(time: time + 0.3)
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

    func testMacOSSwipeSwitchesAndAnEdgeDoesNothing() async throws {
        XCTAssertEqual(controller.beginDockSwipe(incomingFromBelow: false, progress: 0.1, timestamp: 1), .ignored,
                       "No previous workspace: the swipe is kept, so Mission Control does not open")
        XCTAssertEqual(controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 1), .started)
        controller.updateDockSwipe(0.6, timestamp: 1.1)
        let started = expectation(description: "Navigation entered session")
        gate.started = started
        controller.endDockSwipe(commit: true, timestamp: 1.2)
        let task = try XCTUnwrap(controller.pending)
        await fulfillment(of: [started], timeout: 2)
        await finish(task)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[2])
    }

    private func startNavigation(_ action: () -> Void) async throws -> Task<Void, Never> {
        let started = expectation(description: "Navigation entered session")
        gate.started = started
        action()
        let task = try XCTUnwrap(controller.pending)
        await fulfillment(of: [started], timeout: 2)
        gate.started = nil
        return task
    }

    func testAQuickSecondSwipeWaitsForTheFirstSwitchAndContinuesFromThere() async throws {
        XCTAssertEqual(controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 1), .started)
        let first = try await startNavigation { controller.endDockSwipe(commit: true, timestamp: 1.2) }
        XCTAssertEqual(controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 1.3), .started,
                       "A swipe during the switch is kept, not dropped")
        controller.updateDockSwipe(0.7, timestamp: 1.4)
        controller.endDockSwipe(commit: true, timestamp: 1.45)
        let started = expectation(description: "Second navigation entered session")
        gate.started = started
        await finish(first)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[2])
        await fulfillment(of: [started], timeout: 2)
        let second = try XCTUnwrap(controller.pending)
        await finish(second, id: 1)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[3], "Both swipes switched")
    }

    func testASecondSwipeStillMovingWhenTheFirstLandsFollowsTheFingers() async throws {
        XCTAssertEqual(controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 1), .started)
        let first = try await startNavigation { controller.endDockSwipe(commit: true, timestamp: 1.2) }
        XCTAssertEqual(controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 1.3), .started)
        controller.updateDockSwipe(0.3, timestamp: 1.4)
        await finish(first)
        controller.updateDockSwipe(0.2, timestamp: 1.5)
        controller.endDockSwipe(commit: false, timestamp: 1.6)
        XCTAssertNil(controller.pending)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[2])
    }

    func testASecondSwipeTakenBackOrPastTheLastWorkspaceDoesNothing() async throws {
        XCTAssertEqual(controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 1), .started)
        var landing = try await startNavigation { controller.endDockSwipe(commit: true, timestamp: 1.2) }
        _ = controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 1.3)
        controller.endDockSwipe(commit: false, timestamp: 1.4)
        await finish(landing)
        XCTAssertNil(controller.pending)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[2])

        _ = controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 2)
        landing = try await startNavigation { controller.endDockSwipe(commit: true, timestamp: 2.2) }
        _ = controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 2.3)
        controller.endDockSwipe(commit: true, timestamp: 2.4)
        await finish(landing, id: 1)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[3])
        XCTAssertNil(controller.pending, "No workspace beyond the last: the queued swipe ends quietly")
    }

    func testWhileWinMuxXCannotSwitchADragOrTheOverviewKeepsTheSwipeFromMacOS() {
        navigationAllowed = false
        XCTAssertEqual(controller.dockSwipeMayStart(), .unavailable)
        XCTAssertEqual(controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 1), .unavailable)
        keepsSwipe = true
        XCTAssertEqual(controller.dockSwipeMayStart(), .ignored, "Decided at touchdown, before macOS sees any motion")
        XCTAssertEqual(controller.beginDockSwipe(incomingFromBelow: true, progress: 0.1, timestamp: 1), .ignored,
                       "macOS does not switch Spaces under a drag or the overview")
    }

    func testResetDuringNavigationCannotActivateOldWorkspace() async throws {
        begin()
        let task = try await commit()
        controller.reset()
        await finish(task)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
        XCTAssertNil(controller.pending)
    }

    func testOldCompletionCannotCancelNewGestureOrClearItsNavigation() async throws {
        begin()
        let old = try await commit()
        controller.reset()
        begin(time: 3)
        let current = try await commit(time: 3)
        await finish(old)
        XCTAssertNotNil(controller.pending)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
        await finish(current, id: 1)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[2])
        XCTAssertEqual(world.displays[1].activeWorkspace, world.spaces[1])
        XCTAssertEqual(world.displays[2].activeWorkspace, world.spaces[4])
    }

    func testOldFailureCannotCancelNewGestureOrScheduleRecovery() async throws {
        begin()
        let old = try await commit()
        controller.reset()
        begin(time: 3)
        gate.fail = true
        await finish(old)
        XCTAssertEqual(failures, 0)
    }

    func testSourceSwitchDuringGestureRejectsRelease() {
        begin()
        XCTAssertTrue(activateWorkspaceForUser(world.spaces[3], on: world.displays[0]))
        release(time: 1.3)
        XCTAssertNil(controller.pending)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[3])
    }

    func testOwnershipChangeDuringGestureRejectsRelease() {
        begin()
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(world.spaces[2], targetMonitor: world.displays[1]))
        release(time: 1.3)
        XCTAssertNil(controller.pending)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
    }

    func testOwnershipChangeWhileNavigationWaitsIsRevalidated() async throws {
        begin()
        let task = try await commit()
        XCTAssertTrue(activateWorkspaceOnMonitorPreservingSourceViewport(world.spaces[2], targetMonitor: world.displays[1]))
        await finish(task)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
        XCTAssertEqual(world.displays[1].activeWorkspace, world.spaces[2])
    }

    func testRuntimeBecomingUnavailableDuringGestureCancelsIt() {
        begin()
        navigationAllowed = false
        move(1, time: 1.25)
        release(time: 1.3)
        XCTAssertNil(controller.pending)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
    }

    func testRuntimeBecomingUnavailableDuringNavigationRejectsActivation() async throws {
        begin()
        let task = try await commit()
        navigationAllowed = false
        await finish(task)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
    }

    func testNavigationFailureReportsRecovery() async throws {
        gate.fail = true
        begin()
        let task = try await commit()
        await finish(task)
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(world.displays[0].activeWorkspace, world.spaces[0])
    }
}
