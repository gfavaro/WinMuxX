@testable import AppBundle
import XCTest

@MainActor
final class ChangeSignalTest: XCTestCase {
    func testWaitResumesOnTheChangeAndTimesOutWithoutOne() async {
        let signal = ChangeSignal()
        var ready = false
        let started = ContinuousClock.now
        Task { @MainActor in
            ready = true
            signal.notify()
        }
        let result = await signal.wait(timeout: .seconds(5)) { ready }
        XCTAssertTrue(result)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1), "Resumed by the change, not the timeout")

        let quiet = ContinuousClock.now
        let stale = await signal.wait(timeout: .milliseconds(50)) { false }
        XCTAssertFalse(stale)
        XCTAssertGreaterThanOrEqual(quiet.duration(to: .now), .milliseconds(50))
    }

    func testNextChangeReturnsAtTheDeadlineWhenNothingChanges() async {
        let signal = ChangeSignal()
        let started = ContinuousClock.now
        await signal.nextChange(before: .now + .milliseconds(30))
        XCTAssertGreaterThanOrEqual(started.duration(to: .now), .milliseconds(30))
        signal.notify() // No waiter left behind to resume twice.
    }
}
