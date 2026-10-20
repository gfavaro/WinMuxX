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
    func testOverviewAndHorizontalNavigationShareTheSpringCurve() {
        let horizontal = WorkspaceSwipePreviewGeometry.settlingAnimation(from: 0, to: 500, speed: 0, duration: 0.22)
        let overview = WorkspaceGestureAnimation.settlingAnimation(keyPath: "opacity", from: 0, to: 1, speed: 0, duration: 0.22)
        XCTAssertEqual(horizontal.mass, overview.mass)
        XCTAssertEqual(horizontal.stiffness, overview.stiffness)
        XCTAssertEqual(horizontal.damping, overview.damping)
        XCTAssertEqual(horizontal.duration, overview.duration)
        XCTAssertEqual(overview.keyPath, "opacity")
        XCTAssertGreaterThan(overview.duration, 0)
        XCTAssertLessThan(overview.duration, 5)
    }
    func testConfiguredDurationAndAccessibilityDisableMotion() {
        XCTAssertEqual(WorkspaceGestureAnimation.duration(milliseconds: 350, enabled: true, reduceMotion: false), 0.35)
        XCTAssertNil(WorkspaceGestureAnimation.duration(milliseconds: 0, enabled: true, reduceMotion: false))
        XCTAssertNil(WorkspaceGestureAnimation.duration(milliseconds: 220, enabled: false, reduceMotion: false))
        XCTAssertNil(WorkspaceGestureAnimation.duration(milliseconds: 220, enabled: true, reduceMotion: true))
    }
}
