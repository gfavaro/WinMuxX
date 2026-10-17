@testable import AppBundle
import AppKit
import XCTest

final class WindowMotionTest: XCTestCase {
    func testWorkspaceRevealSnapsOnceAndAllowsLaterLayoutAnimation() {
        var policy = WindowMotionDisplayPolicy()
        policy.snapOnNextLayout(42)
        XCTAssertTrue(policy.shouldSnap(42), "Restoration must not animate from the parking corner")
        XCTAssertFalse(policy.shouldSnap(42), "Later layout changes should animate normally")
        policy.snapOnNextLayout(42)
        policy.forget(42)
        XCTAssertFalse(policy.shouldSnap(42), "A closed window must not leave motion state behind")
    }
    func testOddColumnsHaveStableNativeEdgesOnNegativeOriginMonitor() {
        for count in [3, 5, 7] {
            let origin: CGFloat = -908
            let width: CGFloat = 3391
            let frames = (0..<count).map { index in
                windowMotionNativeTarget(CGRect(x: origin + CGFloat(index) * width / CGFloat(count),
                    y: -1440, width: width / CGFloat(count), height: 1399))
            }
            XCTAssertEqual(frames.first?.minX, origin)
            XCTAssertEqual(frames.last?.maxX, origin + width)
            for index in 1..<count { XCTAssertEqual(frames[index - 1].maxX, frames[index].minX) }
            for frame in frames {
                XCTAssertEqual(windowMotionNativeTarget(frame), frame)
                XCTAssertEqual(frame.origin.x, frame.origin.x.rounded())
                XCTAssertEqual(frame.width, frame.width.rounded())
            }
        }
    }
    func testRefreshClockUsesDisplayCadenceAndCapsStalls() {
        XCTAssertEqual(windowMotionFrameDelta(previous: nil, current: 10, fallback: 1.0 / 120), 1.0 / 120)
        XCTAssertEqual(windowMotionFrameDelta(previous: 10, current: 10 + 1.0 / 60, fallback: 0), 1.0 / 60, accuracy: 0.000001)
        XCTAssertEqual(windowMotionFrameDelta(previous: 10, current: 12, fallback: 0), 1.0 / 30)
        XCTAssertEqual(windowMotionFrameDelta(previous: 10, current: 9, fallback: 0), 0)
    }
    func testCrossDisplayMotionDepartsFromNativeFrameAndGoesDirectlyToTile() throws {
        let native = CGRect(x: 300, y: 100, width: 800, height: 600)
        let target = CGRect(x: -1900, y: -1050, width: 900, height: 900)
        let start = try XCTUnwrap(windowMotionDeparture(inFlight: nil, nativeFrame: native, cachedFrame: .zero))
        let motion = WindowMotionFrame(start: start, target: target)
        XCTAssertEqual(motion.frame(progress: 0), native)
        XCTAssertEqual(motion.frame(progress: 1), target)
        XCTAssertEqual(motion.frame(progress: 0.5).minX, (native.minX + target.minX) / 2)
        XCTAssertEqual(motion.frame(progress: 0.5).minY, (native.minY + target.minY) / 2)
    }

    func testRetargetUsesInFlightPositionAndMissingNativeFrameUsesCache() {
        let inFlight = CGRect(x: -100, y: 80, width: 700, height: 500)
        let native = CGRect(x: 300, y: 100, width: 800, height: 600)
        XCTAssertEqual(windowMotionDeparture(inFlight: inFlight, nativeFrame: native, cachedFrame: .zero), inFlight)
        XCTAssertEqual(windowMotionDeparture(inFlight: nil, nativeFrame: nil, cachedFrame: native), native)
        XCTAssertNil(windowMotionDeparture(inFlight: nil, nativeFrame: nil, cachedFrame: nil))
    }

    func testDisplayChangesSnapVisibleAndHiddenWindowsOnce() {
        var policy = WindowMotionDisplayPolicy()
        policy.screensChanged(windowIds: [1, 2])
        XCTAssertTrue(policy.shouldSnap(1))
        XCTAssertTrue(policy.shouldSnap(1), "Transient layouts must not consume the settled snap")
        policy.screensSettled()
        XCTAssertTrue(policy.shouldSnap(1))
        XCTAssertFalse(policy.shouldSnap(1))
        XCTAssertTrue(policy.shouldSnap(2), "Hidden windows snap on their later visit")
        XCTAssertFalse(policy.shouldSnap(2))
        XCTAssertFalse(policy.shouldSnap(3), "New windows can animate normally")
    }

    func testRepeatedDisplayChangesRetainHiddenWindowsAndForgetClosedIds() {
        var policy = WindowMotionDisplayPolicy()
        policy.screensChanged(windowIds: [1, 2])
        policy.screensSettled()
        _ = policy.shouldSnap(1)
        policy.forget(2)
        policy.screensChanged(windowIds: [1, 3])
        policy.screensSettled()
        XCTAssertTrue(policy.shouldSnap(1))
        XCTAssertFalse(policy.shouldSnap(2), "A reused closed ID has no pending motion state")
        XCTAssertTrue(policy.shouldSnap(3))
    }

    func testInterpolationAndExactLanding() {
        let start = CGRect(x: 10, y: 20, width: 100, height: 200)
        let target = CGRect(x: 50, y: 80, width: 300, height: 400)
        let motion = WindowMotionFrame(start: start, target: target)
        XCTAssertEqual(motion.frame(progress: -1), start)
        XCTAssertEqual(motion.frame(progress: 0.5), CGRect(x: 30, y: 50, width: 200, height: 300))
        XCTAssertEqual(motion.frame(progress: 2), target)
    }

    func testRetargetStartsAtCurrentFrame() {
        let initial = WindowMotionFrame(start: .zero, target: CGRect(x: 100, y: 100, width: 400, height: 400))
        let current = initial.frame(progress: 0.4)
        let retargeted = WindowMotionFrame(start: current, target: CGRect(x: 200, y: 50, width: 800, height: 600))
        XCTAssertEqual(retargeted.frame(progress: 0), current)
        XCTAssertEqual(retargeted.frame(progress: 1), retargeted.target)
    }
}
