@testable import AppBundle
import XCTest

final class WorkspaceGestureAnimationTest: XCTestCase {
    func testInteractiveOverviewGeometryIsBoundedAndReversible() {
        for progress in [-1.0, 0, 0.25, 0.5, 1, 2, .nan, .infinity] {
            let motion = WorkspaceOverviewMotion(progress: progress, height: 1000)
            XCTAssertTrue((0...1).contains(motion.opacity))
            XCTAssertTrue((1...1.035).contains(motion.scale))
            XCTAssertTrue((0...60).contains(motion.translation))
        }
        let halfway = WorkspaceOverviewMotion(progress: 0.5, height: 1000)
        XCTAssertEqual(halfway.opacity, 0.5)
        XCTAssertEqual(halfway.translation, 30)
        XCTAssertEqual(WorkspaceOverviewMotion(progress: 1, height: 1000).scale, 1)
    }

    func testSpringCarriesVelocityForOpacityAndScaleWithoutDivisionByZero() {
        let opacity = WorkspaceGestureAnimation.settlingAnimation(keyPath: "opacity", from: 0.5, to: 1, speed: 1, duration: 0.22)
        XCTAssertEqual(opacity.initialVelocity, 2)
        let scale = WorkspaceGestureAnimation.settlingAnimation(keyPath: "transform.scale", from: 1.02, to: 1, speed: -0.04, duration: 0.22)
        XCTAssertEqual(scale.initialVelocity, 2, accuracy: 0.0001)
        let resting = WorkspaceGestureAnimation.settlingAnimation(keyPath: "opacity", from: 1, to: 1, speed: 20, duration: 0.22)
        XCTAssertEqual(resting.initialVelocity, 0)
    }
    func testOverviewSpringIsBounded() {
        let overview = WorkspaceGestureAnimation.settlingAnimation(keyPath: "opacity", from: 0, to: 1, speed: 0, duration: 0.22)
        XCTAssertEqual(overview.keyPath, "opacity")
        XCTAssertGreaterThan(overview.duration, 0)
        XCTAssertLessThan(overview.duration, 5)
    }

    func testReleaseCarriesOnAtTheFingersSpeedWithoutALurch() throws {
        // 1200 pt left, the finger moving 5500 pt/s toward the target.
        let release = WorkspaceSwipePreviewGeometry.settlingAnimation(from: 0, to: 1200, speed: 5500, duration: 0.22)
        let duration = release.duration
        XCTAssertEqual(duration, 1200 / 5500, accuracy: 0.001, "Ends when the finger's speed would have")
        let timing = try XCTUnwrap(release.timingFunction)
        func point(_ index: Int) -> (Double, Double) {
            var values: [Float] = [0, 0]
            timing.getControlPoint(at: index, values: &values)
            return (Double(values[0]), Double(values[1]))
        }
        let (x1, y1) = point(1), (_, y2) = point(2)
        XCTAssertEqual(y1 / x1 * 1200 / duration, 5500, accuracy: 1, "Starts at the finger's speed")
        XCTAssertEqual(y2, 1, "Comes to rest at the end")

        let slow = WorkspaceSwipePreviewGeometry.settlingAnimation(from: 0, to: 1200, speed: 300, duration: 0.22)
        XCTAssertEqual(slow.duration, 0.22, "A slow finger takes the configured time")
        let away = WorkspaceSwipePreviewGeometry.settlingAnimation(from: 0, to: 1200, speed: -3000, duration: 0.22)
        XCTAssertEqual(away.duration, 0.22)
        let quick = WorkspaceSwipePreviewGeometry.settlingAnimation(from: 0, to: 1200, speed: 50000, duration: 0.22)
        XCTAssertEqual(quick.duration, 0.12, "Never shorter than 120 ms")
    }

    func testConfiguredDurationAndAccessibilityDisableMotion() {
        XCTAssertEqual(WorkspaceGestureAnimation.duration(milliseconds: 350, enabled: true, reduceMotion: false), 0.35)
        XCTAssertNil(WorkspaceGestureAnimation.duration(milliseconds: 0, enabled: true, reduceMotion: false))
        XCTAssertNil(WorkspaceGestureAnimation.duration(milliseconds: 220, enabled: false, reduceMotion: false))
        XCTAssertNil(WorkspaceGestureAnimation.duration(milliseconds: 220, enabled: true, reduceMotion: true))
    }
}
