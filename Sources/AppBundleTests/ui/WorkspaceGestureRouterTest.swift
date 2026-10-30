@testable import AppBundle
import AppKit
import XCTest

private func testContacts(_ a: Double, _ b: Double, _ c: Double) -> WorkspaceTouchContacts {
    WorkspaceTouchContacts(first: .init(identifier: 1, y: a), second: .init(identifier: 2, y: b),
                           third: .init(identifier: 3, y: c))
}

final class WorkspaceGestureRouterTest: XCTestCase {
    func testOptionGestureIsReservedForScrollingOnlyInScrollingWorkspaces() {
        XCTAssertEqual(WorkspaceHorizontalGestureRoute.resolve(optionHeldAtStart: false, scrollingEnabledAtStart: true), .workspaceSwipe)
        XCTAssertEqual(WorkspaceHorizontalGestureRoute.resolve(optionHeldAtStart: true, scrollingEnabledAtStart: true), .scrolling)
        XCTAssertEqual(WorkspaceHorizontalGestureRoute.resolve(optionHeldAtStart: true, scrollingEnabledAtStart: false), .ignore)
    }

    private func frame(_ x: Double = 0.5, _ y: Double = 0.5, fingers: Int = 3, device: UInt64 = 1, contacts: UInt64 = 123, time: Double = 1) -> WorkspaceTouchFrame {
        .init(device: device, fingers: fingers, x: x, y: y, timestamp: time, contacts: contacts,
              touchContacts: fingers == 3 ? testContacts(y, y, y) : nil)
    }
    func testHorizontalSequenceRetainsOriginalAnchorAndAxis() throws {
        var router = WorkspaceGestureAxisRouter()
        let start = frame()
        XCTAssertNil(router.route(start))
        let result = try XCTUnwrap(router.route(frame(0.45, 0.501, time: 1.1)))
        XCTAssertEqual(result.0, .horizontal)
        XCTAssertEqual(result.1.first, start)
        XCTAssertEqual(router.route(frame(0.44, 0.8, time: 1.2))?.0, .horizontal)
        XCTAssertEqual(router.route(frame(fingers: 0, time: 1.3))?.0, .horizontal)
        XCTAssertNil(router.axis)
    }
    func testVerticalSequenceCannotAlsoRouteHorizontally() throws {
        var router = WorkspaceGestureAxisRouter()
        _ = router.route(frame())
        XCTAssertEqual(router.route(frame(0.51, 0.6, time: 1.1))?.0, .vertical)
        XCTAssertEqual(router.route(frame(0.9, 0.61, time: 1.2))?.0, .vertical)
        XCTAssertNil(router.route(frame(fingers: 0, device: 2)))
        XCTAssertEqual(router.route(frame(fingers: 0, time: 1.3))?.0, .vertical)
        XCTAssertNil(router.axis)
    }
    func testContactReplacementAndFourFingerSequenceRejectUntilLift() {
        for bad in [frame(0.49, 0.7, contacts: 999, time: 1.1), frame(fingers: 4, time: 1.1), frame(time: 0.5)] {
            var router = WorkspaceGestureAxisRouter()
            _ = router.route(frame()); XCTAssertNil(router.route(bad))
            XCTAssertNil(router.route(frame(0.3, 0.5, time: 1.2)))
            _ = router.route(frame(fingers: 0, time: 1.3))
            XCTAssertNil(router.route(frame(time: 2)))
            XCTAssertEqual(router.route(frame(0.3, 0.5, time: 2.1))?.0, .horizontal)
        }
        var router = WorkspaceGestureAxisRouter()
        XCTAssertNil(router.route(frame(fingers: 4)))
        XCTAssertNil(router.route(frame(0.5, 0.8, time: 1.2)))
    }
    func testInterruptedScrollingContactCannotRestartUntilFullLift() {
        var gate = ScrollingGestureContactGate()
        XCTAssertTrue(gate.allows(frame()))
        gate.interrupt() // Explicit click/focus supersedes the captured offset.
        XCTAssertFalse(gate.allows(frame(0.2, time: 1.1)))
        XCTAssertFalse(gate.allows(frame(0.1, time: 1.2)))
        XCTAssertFalse(gate.allows(frame(fingers: 2, time: 1.3)))
        XCTAssertFalse(gate.allows(frame(fingers: 0, time: 1.4)))
        XCTAssertTrue(gate.allows(frame(time: 2)))
    }
    func testAmbiguousMovementDoesNotChooseAnAxis() {
        var router = WorkspaceGestureAxisRouter()
        _ = router.route(frame())
        XCTAssertNil(router.route(frame(0.56, 0.56, time: 1.1)))
        XCTAssertNil(router.route(frame(fingers: 0, time: 1.2)))
    }

    func testOverviewRequiresAllThreeContactsToMoveInTheSameDirection() {
        for sign in [-1.0, 1.0] {
            var router = WorkspaceGestureAxisRouter()
            var start = frame(time: 1)
            start.touchContacts = testContacts(0.5, 0.5, 0.5)
            XCTAssertNil(router.route(start))
            // Two fingers move a long way while a third remains nearly still.
            var resting = frame(0.5, 0.5 + sign * 0.12, time: 1.1)
            resting.touchContacts = testContacts(0.502, 0.5 + sign * 0.18, 0.5 + sign * 0.18)
            XCTAssertNil(router.route(resting))
            XCTAssertNil(router.axis)
            // Once every contact moves together, the same sequence can start.
            var moving = frame(0.5, 0.5 + sign * 0.13, time: 1.2)
            moving.touchContacts = testContacts(0.5 + sign * 0.018, 0.5 + sign * 0.18, 0.5 + sign * 0.19)
            XCTAssertEqual(router.route(moving)?.0, .vertical)
            // Recognition stays locked through a reversal or an uneven finger.
            moving.touchContacts = testContacts(0.5, 0.5, 0.5)
            XCTAssertEqual(router.route(moving)?.0, .vertical)
        }
    }

    func testOverviewRejectsMissingOrReplacedIndividualContacts() {
        var router = WorkspaceGestureAxisRouter()
        _ = router.route(frame())
        var missing = frame(0.5, 0.7, time: 1.1)
        missing.touchContacts = nil
        XCTAssertNil(router.route(missing))
        var replaced = frame(0.5, 0.7, time: 1.2)
        replaced.touchContacts = .init(first: .init(identifier: 99, y: 0.7),
                                       second: .init(identifier: 2, y: 0.7),
                                       third: .init(identifier: 3, y: 0.7))
        XCTAssertNil(router.route(replaced))
        XCTAssertNil(router.axis)
    }

    func testOverviewRejectsEachPossibleRestingContact() {
        for resting in 0..<3 {
            var router = WorkspaceGestureAxisRouter()
            _ = router.route(frame())
            var sample = frame(0.5, 0.7, time: 1.1)
            let ys = (0..<3).map { $0 == resting ? 0.5 : 0.8 }
            sample.touchContacts = testContacts(ys[0], ys[1], ys[2])
            XCTAssertNil(router.route(sample), "resting contact \(resting)")
        }
    }
    func testTransformedVerticalRecognizerCommitsOnlyAtLiftAndRejectsReversal() {
        for reversed in [false, true] {
            var router = WorkspaceGestureAxisRouter()
            var recognizer = WorkspaceTouchRecognizer()
            var events: [WorkspaceTouchRecognizer.Event] = []
            for frame in [frame(), frame(0.5, 0.65, time: 1.1), frame(0.5, reversed ? 0.51 : 0.7, time: 1.2), frame(fingers: 0, time: 1.3)] {
                guard let (axis, frames) = router.route(frame), axis == .vertical else { continue }
                for item in frames {
                    let transformed = WorkspaceTouchFrame(device: item.device, fingers: item.fingers, x: 1 - item.y, y: item.x,
                        timestamp: item.timestamp, contacts: item.contacts)
                    if let event = recognizer.receive(transformed, displayPoint: .zero, reversed: false) { events.append(event) }
                }
            }
            XCTAssertEqual(events.last, .ended(!reversed))
            XCTAssertFalse(events.dropLast().contains(.ended(true)))
        }
    }
}

@MainActor
final class WorkspaceGestureIntegrationTest: XCTestCase {
    func testRestingFingerCannotOpenOverviewAndRealSwipeStillTracks() {
        var open = false, updates: [Double] = []
        let router = WorkspaceGestureRouter(dependencies: .init(horizontalEnabled: { false }, overviewEnabled: { true },
            overviewIsOpen: { open }, horizontal: { _ in XCTFail() }, show: { XCTFail() }, hide: { XCTFail() },
            beginOverviewGesture: { _, progress in open = true; updates.append(progress); return true },
            updateOverviewGesture: { updates.append($0) }, endOverviewGesture: { _, _ in }))
        router.handle(frame())
        var resting = frame(0.5, 0.7, time: 1.1)
        resting.touchContacts = testContacts(0.5, 0.8, 0.8)
        router.handle(resting)
        XCTAssertFalse(open)
        router.handle(frame(fingers: 0, time: 1.2))
        router.handle(frame(time: 2))
        router.handle(frame(0.5, 0.56, time: 2.1))
        router.handle(frame(0.5, 0.7, time: 2.2))
        XCTAssertTrue(open)
        XCTAssertGreaterThan(updates.last ?? 0, updates.first ?? 1)
    }
    func testInteractiveOpeningTracksBeforeLiftAndCommitsEvenThoughOverviewIsAlreadyOpen() {
        var open = false, progress: [Double] = [], endings: [Bool] = []
        let router = WorkspaceGestureRouter(dependencies: .init(horizontalEnabled: { false }, overviewEnabled: { true },
            overviewIsOpen: { open }, horizontal: { _ in XCTFail() }, show: { XCTFail("Interactive path must not show twice") },
            hide: { XCTFail() }, beginOverviewGesture: { opening, p in
                XCTAssertTrue(opening); open = true; progress.append(p); return true
            }, updateOverviewGesture: { progress.append($0) }, endOverviewGesture: { commit, speed in
                endings.append(commit); XCTAssertTrue(speed.isFinite)
            }))
        router.handle(frame()); router.handle(frame(0.5, 0.56, time: 1.05))
        XCTAssertTrue(open)
        XCTAssertTrue(endings.isEmpty)
        router.handle(frame(0.5, 0.68, time: 1.1))
        XCTAssertEqual(progress.count, 2)
        XCTAssertGreaterThan(progress[1], progress[0])
        router.handle(frame(fingers: 2, time: 1.12)); router.handle(frame(fingers: 0, time: 1.13))
        XCTAssertEqual(endings, [true])
    }

    func testInteractiveReversalAndResetCancelExactlyOnce() {
        var endings: [Bool] = []
        let router = WorkspaceGestureRouter(dependencies: .init(horizontalEnabled: { false }, overviewEnabled: { false },
            overviewIsOpen: { true }, horizontal: { _ in }, show: { XCTFail() }, hide: { XCTFail() },
            beginOverviewGesture: { opening, _ in XCTAssertFalse(opening); return true },
            updateOverviewGesture: { _ in }, endOverviewGesture: { endings.append($0); _ = $1 }))
        for item in [frame(), frame(0.5, 0.4, time: 1.05), frame(0.5, 0.49, time: 1.1), frame(fingers: 0, time: 1.2)] { router.handle(item) }
        XCTAssertEqual(endings, [false])
        router.handle(frame(time: 2)); router.handle(frame(0.5, 0.4, time: 2.05))
        router.reset(); router.reset(); router.handle(frame(fingers: 0, time: 2.1))
        XCTAssertEqual(endings, [false, false])
    }

    func testMotionDisabledFallbackStillCommitsOnRelease() {
        var open = false
        let router = WorkspaceGestureRouter(dependencies: .init(horizontalEnabled: { false }, overviewEnabled: { true },
            overviewIsOpen: { open }, horizontal: { _ in }, show: { open = true }, hide: {},
            beginOverviewGesture: { _, _ in false }, endOverviewGesture: { _, _ in XCTFail() }))
        router.handle(frame()); router.handle(frame(0.5, 0.7, time: 1.1))
        XCTAssertFalse(open)
        router.handle(frame(fingers: 0, time: 1.2))
        XCTAssertTrue(open)
    }
    private func frame(_ x: Double = 0.5, _ y: Double = 0.5, fingers: Int = 3, time: Double = 1) -> WorkspaceTouchFrame {
        .init(device: 1, fingers: fingers, x: x, y: y, timestamp: time, contacts: 123,
              touchContacts: fingers == 3 ? testContacts(y, y, y) : nil)
    }
    func testIndependentFeatureFlagsAndVerticalCommands() {
        for horizontal in [false, true] {
            for overview in [false, true] {
                var open = false, shows = 0, hides = 0, horizontalFrames = 0
                let router = WorkspaceGestureRouter(dependencies: .init(horizontalEnabled: { horizontal },
                    overviewEnabled: { overview }, overviewIsOpen: { open }, horizontal: { _ in horizontalFrames += 1 },
                    show: { open = true; shows += 1 }, hide: { open = false; hides += 1 }))
                for item in [frame(), frame(0.3, time: 1.1), frame(fingers: 0, time: 1.2)] { router.handle(item) }
                XCTAssertEqual(horizontalFrames, horizontal ? 3 : 0)
                for item in [frame(time: 2), frame(0.5, 0.7, time: 2.1)] { router.handle(item) }
                XCTAssertEqual(shows, 0)
                router.handle(frame(fingers: 0, time: 2.2))
                XCTAssertEqual(shows, overview ? 1 : 0)
                for item in [frame(time: 3), frame(0.5, 0.3, time: 3.1), frame(fingers: 0, time: 3.2)] { router.handle(item) }
                XCTAssertEqual(hides, overview ? 1 : 0)
                XCTAssertFalse(open)
            }
        }
    }
    func testCommandOpenedOverviewClosesWithShortDownwardSwipeWithoutUpwardShortcut() {
        var open = true, hides = 0
        let router = WorkspaceGestureRouter(dependencies: .init(horizontalEnabled: { false }, overviewEnabled: { false },
            overviewIsOpen: { open }, horizontal: { _ in XCTFail("Vertical gesture routed horizontally") },
            show: { XCTFail("Upward shortcut is disabled") }, hide: { open = false; hides += 1 }))
        for item in [frame(), frame(0.5, 0.42, time: 1.4), frame(fingers: 2, time: 1.7), frame(fingers: 0, time: 1.8)] { router.handle(item) }
        XCTAssertFalse(open)
        XCTAssertEqual(hides, 1)
        for item in [frame(time: 2), frame(0.5, 0.8, time: 2.2), frame(fingers: 0, time: 2.3)] { router.handle(item) }
        XCTAssertFalse(open)
    }
    func testDownwardReversalDoesNotDismissAndSourceDemandIsScoped() {
        var hides = 0
        let router = WorkspaceGestureRouter(dependencies: .init(horizontalEnabled: { false }, overviewEnabled: { false },
            overviewIsOpen: { true }, horizontal: { _ in }, show: {}, hide: { hides += 1 }))
        for item in [frame(), frame(0.5, 0.4, time: 1.1), frame(0.5, 0.49, time: 1.3), frame(fingers: 0, time: 1.5)] { router.handle(item) }
        XCTAssertEqual(hides, 0)
        XCTAssertTrue(workspaceGesturesNeedRawTouch(horizontal: false, overview: false, overviewOpen: true, runtimeEnabled: true))
        XCTAssertFalse(workspaceGesturesNeedRawTouch(horizontal: false, overview: false, overviewOpen: false, runtimeEnabled: true))
        XCTAssertFalse(workspaceGesturesNeedRawTouch(horizontal: true, overview: true, overviewOpen: true, runtimeEnabled: false))
    }
    func testConfigurationDisableOrResetDuringGestureCannotOpen() {
        var enabled = true, shows = 0
        let router = WorkspaceGestureRouter(dependencies: .init(horizontalEnabled: { false }, overviewEnabled: { enabled },
            overviewIsOpen: { false }, horizontal: { _ in XCTFail("Vertical event routed horizontally") },
            show: { shows += 1 }, hide: { XCTFail("Unexpected dismissal") }))
        router.handle(frame()); router.handle(frame(0.5, 0.7, time: 1.1))
        enabled = false; router.handle(frame(fingers: 0, time: 1.2)); XCTAssertEqual(shows, 0)
        enabled = true; router.handle(frame(time: 2)); router.handle(frame(0.5, 0.7, time: 2.1))
        router.reset(); router.handle(frame(fingers: 0, time: 2.2)); XCTAssertEqual(shows, 0)
    }
}
