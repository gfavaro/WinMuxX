@testable import AppBundle
import XCTest

@MainActor
private final class ScrollingLifecycleReceiver: DockSwipeReceiver {
    var progress: [Double] = []
    var endings: [Bool] = []
    var starts = 0

    func dockSwipeMayStart() -> DockSwipeStart { .started }
    func dockSwipeBegan(positive: Bool, progress: Double, timestamp: Double) -> DockSwipeStart {
        starts += 1
        return .started
    }
    func dockSwipeChanged(_ progress: Double, timestamp: Double) { self.progress.append(progress) }
    func dockSwipeEnded(commit: Bool, progress: Double, velocity: Double, timestamp: Double) { endings.append(commit) }
}

@MainActor
final class ScrollingGestureLifecycleTest: XCTestCase {
    func testAbandonCancelsOnceAndLateEventsDoNotReachReceiver() {
        var tracker = DockSwipeTracker(dockNeedsEnd: true)
        let receiver = ScrollingLifecycleReceiver()
        _ = tracker.receive(phase: 1, progress: 0, endVelocity: 0, timestamp: 0, to: receiver)
        _ = tracker.receive(phase: 2, progress: 0.2, endVelocity: 0, timestamp: 0.1, to: receiver)
        _ = tracker.receive(phase: 2, progress: 0.4, endVelocity: 0, timestamp: 0.2, to: receiver)
        XCTAssertEqual(receiver.starts, 1)
        XCTAssertEqual(receiver.progress, [0.4])
        tracker.abandon(receiver)
        tracker.abandon(receiver)
        _ = tracker.receive(phase: 2, progress: 0.8, endVelocity: 0, timestamp: 0.3, to: receiver)
        _ = tracker.receive(phase: 4, progress: 0.8, endVelocity: 0, timestamp: 0.4, to: receiver)
        XCTAssertEqual(receiver.progress, [0.4])
        XCTAssertEqual(receiver.endings, [false])
        XCTAssertFalse(tracker.ownsGesture)
    }

    func testNewGestureAfterAbandonCanComplete() {
        var tracker = DockSwipeTracker(dockNeedsEnd: true)
        let receiver = ScrollingLifecycleReceiver()
        _ = tracker.receive(phase: 1, progress: 0, endVelocity: 0, timestamp: 0, to: receiver)
        _ = tracker.receive(phase: 2, progress: 0.2, endVelocity: 0, timestamp: 0.1, to: receiver)
        tracker.abandon(receiver)
        _ = tracker.receive(phase: 1, progress: 0, endVelocity: 0, timestamp: 1, to: receiver)
        _ = tracker.receive(phase: 2, progress: 0.7, endVelocity: 0, timestamp: 1.1, to: receiver)
        _ = tracker.receive(phase: 4, progress: 0.7, endVelocity: 0, timestamp: 1.2, to: receiver)
        XCTAssertEqual(receiver.starts, 2)
        XCTAssertEqual(receiver.endings, [false, true])
        XCTAssertFalse(tracker.ownsGesture)
    }
}
