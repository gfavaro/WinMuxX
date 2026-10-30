@testable import AppBundle
import XCTest

@MainActor
private final class DockSwipeReceiverSpy: DockSwipeReceiver {
    var mayStart = DockSwipeStart.started
    var start = DockSwipeStart.started
    var began: [Bool] = []
    var progress: [Double] = []
    var ended: [Bool] = []

    func dockSwipeMayStart() -> DockSwipeStart { mayStart }
    func dockSwipeBegan(slidesLeft: Bool, progress: Double, timestamp: Double) -> DockSwipeStart {
        began.append(slidesLeft)
        return start
    }
    func dockSwipeChanged(_ progress: Double, timestamp: Double) { self.progress.append(progress) }
    func dockSwipeEnded(commit: Bool, timestamp: Double) { ended.append(commit) }
}

@MainActor
final class DockSwipeTrackerTest: XCTestCase {
    private var tracker = DockSwipeTracker(dockNeedsEnd: true)
    private var receiver = DockSwipeReceiverSpy()

    private func send(_ phase: DockSwipeTracker.Phase, _ progress: Double = 0, velocity: Double = 0,
                      at time: Double) -> DockSwipeTracker.Verdict {
        tracker.receive(phase: phase.rawValue, progress: progress, endVelocity: velocity, timestamp: time, to: receiver)
    }

    func testASwipeWinMuxXCanTakeIsKeptFromTheDockAndFollowsMacOSProgress() {
        XCTAssertEqual(send(.began, at: 0), .hold)
        XCTAssertEqual(send(.changed, 0.02, at: 0.01), .hold, "Touchdown wobble does not choose a direction")
        XCTAssertEqual(send(.changed, -0.1, at: 0.02), .swallow)
        XCTAssertEqual(receiver.began, [false], "Negative progress heads for the previous Space")
        XCTAssertTrue(tracker.ownsGesture)
        XCTAssertEqual(send(.changed, -0.4, at: 0.1), .swallow)
        XCTAssertEqual(send(.changed, -0.7, at: 0.2), .swallow)
        XCTAssertEqual(receiver.progress, [0.4, 0.7])
        XCTAssertEqual(send(.ended, -0.7, at: 0.21), .passWithoutMotion, "macOS 27's Dock still sees the gesture close")
        XCTAssertEqual(receiver.ended, [true])
        XCTAssertFalse(tracker.ownsGesture)
        XCTAssertEqual(tracker.summary.outcome, "switched")
    }

    func testOlderMacOSNeverSeesTheEnd() {
        tracker = DockSwipeTracker(dockNeedsEnd: false)
        _ = send(.began, at: 0)
        _ = send(.changed, 0.3, at: 0.05)
        XCTAssertEqual(send(.ended, 0.3, at: 0.06), .swallow)
    }

    func testTakingTheSwipeBackCancelsIt() {
        _ = send(.began, at: 0)
        _ = send(.changed, 0.3, at: 0.05)
        _ = send(.changed, 0.6, at: 0.15)
        _ = send(.changed, 0.2, at: 0.3)
        _ = send(.changed, -0.1, at: 0.4)
        XCTAssertEqual(receiver.progress.last, 0, "Crossing back past the start never previews the other way")
        _ = send(.ended, -0.1, at: 0.41)
        XCTAssertEqual(receiver.ended, [false])
    }

    func testAQuickFlickSwitchesAndASlowShortSwipeDoesNot() {
        _ = send(.began, at: 0)
        _ = send(.changed, 0.06, at: 0.01)
        _ = send(.changed, 0.12, at: 0.03)
        _ = send(.changed, 0.2, at: 0.05)
        _ = send(.ended, 0.2, at: 0.06)
        XCTAssertEqual(receiver.ended, [true])

        _ = send(.began, at: 1)
        _ = send(.changed, 0.06, at: 1.1)
        _ = send(.changed, 0.2, at: 1.5)
        _ = send(.ended, 0.2, at: 1.51)
        XCTAssertEqual(receiver.ended, [true, false])

        _ = send(.began, at: 2)
        _ = send(.changed, 0.06, at: 2.01)
        _ = send(.changed, 0.3, at: 2.05)
        _ = send(.ended, 0.3, at: 2.5)
        XCTAssertEqual(receiver.ended, [true, false, false], "Fingers that rested before lifting are not a flick")
    }

    func testAFlickThatEndsBeforeAnyTravelUsesTheEndVelocity() {
        _ = send(.began, at: 0)
        XCTAssertEqual(send(.ended, velocity: 3, at: 0.02), .passWithoutMotion)
        XCTAssertEqual(receiver.began, [true])
        XCTAssertEqual(receiver.ended, [true])
    }

    func testWithNoWorkspaceThatWayMacOSGetsTheWholeSwipe() {
        receiver.start = .unavailable
        XCTAssertEqual(send(.began, at: 0), .hold)
        XCTAssertEqual(send(.changed, 0.01, at: 0.01), .hold)
        XCTAssertEqual(send(.changed, 0.08, at: 0.02), .replayHeldThenPass)
        XCTAssertFalse(tracker.ownsGesture)
        XCTAssertEqual(send(.changed, 0.5, at: 0.1), .pass)
        XCTAssertEqual(send(.ended, 0.5, at: 0.2), .pass, "macOS ends its own swipe with its motion")
        XCTAssertEqual(receiver.progress, [])
        XCTAssertEqual(receiver.ended, [])
        XCTAssertEqual(tracker.summary.outcome, "left to macOS")
    }

    func testWhenWinMuxXIsNotTakingSwipesNothingIsHeld() {
        receiver.mayStart = .unavailable
        XCTAssertEqual(send(.began, at: 0), .pass)
        XCTAssertEqual(send(.changed, 0.3, at: 0.1), .pass)
        XCTAssertEqual(send(.ended, 0.3, at: 0.2), .pass)
        XCTAssertEqual(receiver.began, [])
    }

    func testAnIgnoredSwipeNeverReachesTheDockOrSwitches() {
        receiver.mayStart = .ignored
        XCTAssertEqual(send(.began, at: 0), .swallow)
        XCTAssertTrue(tracker.ownsGesture)
        XCTAssertEqual(send(.changed, 0.6, at: 0.1), .swallow)
        XCTAssertEqual(send(.ended, 0.6, at: 0.2), .passWithoutMotion)
        XCTAssertEqual(receiver.began, [])
        XCTAssertEqual(receiver.ended, [])
    }

    func testASwipeWithoutDirectionGoesBackToMacOS() {
        _ = send(.began, at: 0)
        _ = send(.changed, 0.01, at: 0.01)
        XCTAssertEqual(send(.ended, at: 0.02), .replayHeldThenPass)
        XCTAssertEqual(receiver.began, [])
    }

    func testCancellingOrLosingTheEventsEndsWithoutSwitching() {
        _ = send(.began, at: 0)
        _ = send(.changed, 0.7, at: 0.1)
        XCTAssertEqual(send(.cancelled, at: 0.2), .swallow)
        XCTAssertEqual(receiver.ended, [false])

        _ = send(.began, at: 1)
        _ = send(.changed, 0.7, at: 1.1)
        _ = send(.began, at: 2)
        XCTAssertEqual(receiver.ended, [false, false], "A new swipe closes one whose end never arrived")

        _ = send(.changed, 0.7, at: 2.1)
        tracker.abandon(receiver)
        XCTAssertEqual(receiver.ended, [false, false, false])
        XCTAssertFalse(tracker.ownsGesture)
    }
}
