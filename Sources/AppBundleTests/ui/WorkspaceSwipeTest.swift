@testable import AppBundle
import AppKit
import PrivateApi
import XCTest

final class WorkspaceSwipeTest: XCTestCase {
    private let main = CGPoint(x: 0, y: 0)
    private let external = CGPoint(x: 1920, y: 0)

    private func frame(_ x: Double = 0.5, y: Double = 0.5, fingers: Int = 3,
                       time: Double = 1, device: UInt64 = 1, contacts: UInt64 = 123) -> WorkspaceTouchFrame {
        WorkspaceTouchFrame(device: device, fingers: fingers, x: x, y: y, timestamp: time, contacts: contacts)
    }

    func testPreviewFollowsFingersAndOnlyReleaseCommits() {
        var recognizer = WorkspaceTouchRecognizer()
        XCTAssertNil(recognizer.receive(frame(), displayPoint: external, reversed: false))
        guard case .began(let request) = recognizer.receive(frame(0.45, time: 1.1), displayPoint: main, reversed: false) else {
            return XCTFail("Expected preview intent")
        }
        XCTAssertEqual(request.displayPoint, external)
        XCTAssertTrue(request.isNext)
        XCTAssertTrue(request.slidesLeft)
        XCTAssertEqual(request.progress, 0.05 / 0.24, accuracy: 0.0001)
        guard case .changed(let progress) = recognizer.receive(frame(0.25, time: 1.2), displayPoint: main, reversed: false) else {
            return XCTFail("Expected progress, never an early commit")
        }
        XCTAssertEqual(progress, 1, accuracy: 0.0001)
        XCTAssertEqual(recognizer.receive(frame(fingers: 2, time: 1.3), displayPoint: main, reversed: false), .ended(true))
        XCTAssertNil(recognizer.receive(frame(0.2, fingers: 2, time: 1.4), displayPoint: main, reversed: false))
        XCTAssertNil(recognizer.receive(frame(fingers: 0, time: 2), displayPoint: main, reversed: false))
    }

    func testShorterSwipeCommitsAtTwelvePercentTravel() {
        for (travel, commits) in [(0.119, false), (0.121, true)] {
            var recognizer = WorkspaceTouchRecognizer()
            _ = recognizer.receive(frame(), displayPoint: main, reversed: false)
            _ = recognizer.receive(frame(0.5 - travel, time: 1.1), displayPoint: main, reversed: false)
            XCTAssertEqual(recognizer.receive(frame(fingers: 0, time: 1.2), displayPoint: main, reversed: false), .ended(commits))
        }
    }

    func testQuickFlickCommitsButPausedOrRetractedFlickCancels() {
        for (releaseTime, retract, commits) in [(1.07, false, true), (1.3, false, false), (1.09, true, false)] {
            var recognizer = WorkspaceTouchRecognizer()
            _ = recognizer.receive(frame(), displayPoint: main, reversed: false)
            _ = recognizer.receive(frame(0.47, time: 1.03), displayPoint: main, reversed: false)
            _ = recognizer.receive(frame(0.44, time: 1.06), displayPoint: main, reversed: false)
            if retract { _ = recognizer.receive(frame(0.46, time: 1.08), displayPoint: main, reversed: false) }
            XCTAssertEqual(recognizer.receive(frame(fingers: 0, time: releaseTime), displayPoint: main, reversed: false), .ended(commits))
        }
    }

    func testShortSwipeAndRetractionCancelOnRelease() {
        for endX in [0.45, 0.49] {
            var recognizer = WorkspaceTouchRecognizer()
            _ = recognizer.receive(frame(), displayPoint: main, reversed: false)
            _ = recognizer.receive(frame(0.25, time: 1.1), displayPoint: main, reversed: false)
            _ = recognizer.receive(frame(endX, time: 1.2), displayPoint: main, reversed: false)
            XCTAssertEqual(recognizer.receive(frame(fingers: 0, time: 1.3), displayPoint: main, reversed: false), .ended(false))
        }
    }

    func testReversalChangesTargetButPreviewStillFollowsPhysicalMotion() {
        var recognizer = WorkspaceTouchRecognizer()
        XCTAssertNil(recognizer.receive(frame(fingers: 2), displayPoint: main, reversed: true))
        XCTAssertNil(recognizer.receive(frame(0.2, fingers: 2, time: 1.1), displayPoint: main, reversed: true))
        _ = recognizer.receive(frame(fingers: 0, time: 2), displayPoint: main, reversed: true)
        _ = recognizer.receive(frame(time: 3), displayPoint: main, reversed: true)
        guard case .began(let request) = recognizer.receive(frame(0.25, time: 3.2), displayPoint: main, reversed: true) else {
            return XCTFail("Expected preview")
        }
        XCTAssertFalse(request.isNext)
        XCTAssertTrue(request.slidesLeft)
        XCTAssertEqual(recognizer.receive(frame(fingers: 0, time: 3.3), displayPoint: main, reversed: true), .ended(true))
    }

    func testVerticalGestureNeverBeginsPreview() {
        var recognizer = WorkspaceTouchRecognizer()
        _ = recognizer.receive(frame(), displayPoint: main, reversed: false)
        XCTAssertNil(recognizer.receive(frame(y: 0.65, time: 1.1), displayPoint: main, reversed: false))
        XCTAssertNil(recognizer.receive(frame(0.2, time: 1.2), displayPoint: main, reversed: false))
    }

    func testInvalidContactsCancelPreviewUntilAllFingersLift() {
        for invalid in [frame(fingers: 4, time: 1.2), frame(time: 1.2, contacts: 999),
                        frame(.nan, time: 1.2), frame(time: 12)] {
            var recognizer = WorkspaceTouchRecognizer()
            _ = recognizer.receive(frame(), displayPoint: main, reversed: false)
            _ = recognizer.receive(frame(0.45, time: 1.1), displayPoint: main, reversed: false)
            XCTAssertEqual(recognizer.receive(invalid, displayPoint: main, reversed: false), .cancelled)
            XCTAssertNil(recognizer.receive(frame(0.2, time: 13), displayPoint: main, reversed: false))
            _ = recognizer.receive(frame(fingers: 0, time: 14), displayPoint: main, reversed: false)
            _ = recognizer.receive(frame(time: 15), displayPoint: main, reversed: false)
            XCTAssertNotNil(recognizer.receive(frame(0.25, time: 15.1), displayPoint: main, reversed: false))
        }
    }

    func testOtherDevicesCannotFinishOrRetargetOwnedGesture() {
        var recognizer = WorkspaceTouchRecognizer()
        _ = recognizer.receive(frame(), displayPoint: external, reversed: false)
        _ = recognizer.receive(frame(0.25, time: 1.1), displayPoint: main, reversed: false)
        XCTAssertNil(recognizer.receive(frame(fingers: 0, time: 1.2, device: 2), displayPoint: main, reversed: false))
        XCTAssertNil(recognizer.receive(frame(0.2, time: 1.3, device: 2), displayPoint: main, reversed: false))
        XCTAssertEqual(recognizer.receive(frame(fingers: 0, time: 1.4), displayPoint: main, reversed: false), .ended(true))
    }

    func testCancellationRequiresLiftBeforeRearming() {
        var recognizer = WorkspaceTouchRecognizer()
        _ = recognizer.receive(frame(), displayPoint: main, reversed: false)
        recognizer.cancel()
        XCTAssertNil(recognizer.receive(frame(0.2, time: 1.2), displayPoint: main, reversed: false))
        _ = recognizer.receive(frame(fingers: 0, time: 2), displayPoint: main, reversed: false)
        _ = recognizer.receive(frame(time: 3), displayPoint: main, reversed: false)
        XCTAssertNotNil(recognizer.receive(frame(0.2, time: 3.1), displayPoint: main, reversed: false))
    }

    func testPreviewResistanceIncreasesWithoutChangingDirectionOrReachingTheEdge() {
        XCTAssertEqual(WorkspaceSwipePreviewGeometry.resistedProgress(0), 0)
        XCTAssertEqual(WorkspaceSwipePreviewGeometry.resistedProgress(1), 0.55 / 1.55, accuracy: 0.0001)
        var previous = 0.0
        var previousStep = 1.0
        for step in 1...100 {
            let input = Double(step) / 100
            let output = WorkspaceSwipePreviewGeometry.resistedProgress(input)
            let delta = output - previous
            XCTAssertGreaterThan(delta, 0)
            XCTAssertLessThan(delta, previousStep)
            XCTAssertLessThan(output, input)
            previous = output
            previousStep = delta
        }
        XCTAssertEqual(WorkspaceSwipePreviewGeometry.resistedProgress(-1), 0)
        XCTAssertEqual(WorkspaceSwipePreviewGeometry.resistedProgress(2), 0.55 / 1.55, accuracy: 0.0001)
    }

    func testPreviewOffsetsMeetWithoutGapInBothDirections() {
        for slidesLeft in [false, true] {
            for progress in [0.0, 0.25, 0.5, 1.0] {
                let offsets = WorkspaceSwipePreviewGeometry.offsets(width: 1920, progress: progress, slidesLeft: slidesLeft)
                XCTAssertEqual(abs(offsets.incoming - offsets.outgoing), 1920)
                XCTAssertEqual(abs(offsets.outgoing), 1920 * progress)
            }
        }
    }

    func testMailboxCoalescesMovementButKeepsAnchorAndLift() {
        let mailbox = WorkspaceTouchMailbox()
        mailbox.activate(1)
        XCTAssertFalse(mailbox.offer(frame(), generation: 2))
        XCTAssertTrue(mailbox.offer(frame(), generation: 1))
        for i in 1...100 {
            XCTAssertFalse(mailbox.offer(frame(0.5 - Double(i) / 1000, time: 1 + Double(i) / 1000), generation: 1))
        }
        XCTAssertFalse(mailbox.offer(frame(fingers: 0, time: 2), generation: 1))
        let batch = mailbox.take()
        XCTAssertEqual(batch.frames.count, 3)
        XCTAssertEqual(batch.frames.first?.x, 0.5)
        XCTAssertEqual(batch.frames[1].x, 0.4)
        XCTAssertEqual(batch.frames.last?.fingers, 0)
        XCTAssertEqual(batch.received, 102)
        XCTAssertTrue(mailbox.offer(frame(time: 3), generation: 1))
        mailbox.activate(2)
        XCTAssertFalse(mailbox.offer(frame(), generation: 1))
        XCTAssertTrue(mailbox.take().frames.isEmpty)
    }

    func testOrdinaryTwoFingerMovementDoesNotSchedulePerFrameWork() {
        let mailbox = WorkspaceTouchMailbox()
        mailbox.activate(1)
        XCTAssertTrue(mailbox.offer(frame(fingers: 2), generation: 1))
        _ = mailbox.take()
        for i in 1...100 {
            XCTAssertFalse(mailbox.offer(frame(0.5 + Double(i) / 1000, fingers: 2, time: 1.1), generation: 1))
        }
        XCTAssertTrue(mailbox.take().frames.isEmpty)
        XCTAssertTrue(mailbox.offer(frame(fingers: 0, time: 2), generation: 1))
    }

    func testMailboxOverflowCancelsRatherThanJoiningUnrelatedFrames() {
        let mailbox = WorkspaceTouchMailbox()
        mailbox.activate(1)
        for i in 0..<40 { _ = mailbox.offer(frame(time: Double(i), contacts: UInt64(i)), generation: 1) }
        let frames = mailbox.take().frames
        XCTAssertLessThanOrEqual(frames.count, 32)
        XCTAssertEqual(frames.first?.fingers, -1)
    }

    func testDriverCallbackRunsFromBackgroundThreadWithoutActorAssertion() async {
        RawWorkspaceTouchSource.mailbox.activate(12345)
        let callback: WinMuxTouchFrameCallback = workspaceTouchFrameCallback
        defer { RawWorkspaceTouchSource.mailbox.activate(0) }
        let completed = expectation(description: "background driver callback completed")
        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            callback(12345, 1, 3, 0.5, 0.5, 1, 123)
            callback(12345, 1, 3, 0.3, 0.5, 1.1, 123)
            callback(12345, 1, 0, 0, 0, 1.2, 0)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 2)
    }

    @MainActor
    func testConfigurationIsOptInAndStopIsIdempotent() {
        XCTAssertFalse(Config().workspaceSwipe.enabled)
        let parsed = parseConfig("config-version = 2\n[workspace-swipe]\nenabled = true\nreverse-direction = true")
        XCTAssertTrue(parsed.errors.isEmpty)
        XCTAssertTrue(parsed.config.workspaceSwipe.enabled)
        XCTAssertTrue(parsed.config.workspaceSwipe.reverseDirection)
        XCTAssertFalse(parseConfig("[workspace-swipe]\nenabled = 'yes'").errors.isEmpty)
        RawWorkspaceTouchSource.shared.stop()
        RawWorkspaceTouchSource.shared.stop()
        XCTAssertEqual(RawWorkspaceTouchSource.shared.deviceCount, 0)
        XCTAssertEqual(RawWorkspaceTouchSource.shared.frameCount, 0)
    }
}
