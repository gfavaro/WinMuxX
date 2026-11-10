@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class UnansweredAppIsolationTest: XCTestCase {
    private var fixture: WorkspaceNavigationFixture!

    override func setUp() async throws {
        try await super.setUp()
        fixture = WorkspaceNavigationFixture()
        TrayMenuModel.shared.isEnabled = true
    }

    override func tearDown() async throws {
        fixture.cleanUp()
        fixture = nil
        try await super.tearDown()
    }

    func testAWindowWhoseAppDoesNotAnswerDoesNotStopTheOtherDisplaysBeingLaidOut() async throws {
        let unanswered = TestWindow.new(id: 950, parent: fixture.spaces[0])
        var reads = 0
        unanswered.rectReader = {
            reads += 1
            throw AXReadFailure(code: .cannotComplete)
        }

        try await runRefreshSessionBlocking(.ax(kAXWindowCreatedNotification as String))

        XCTAssertGreaterThan(reads, 0)
        for space in [fixture.spaces[0], fixture.spaces[1], fixture.spaces[4]] {
            let tile = try XCTUnwrap(space.rootTilingContainer.allLeafWindowsRecursive.first)
            XCTAssertNotNil(tile.lastAppliedLayoutPhysicalRect, "workspace \(space.name) was not laid out")
        }
    }

    func testACancelledSessionStillStopsAtAnUnansweredRead() async throws {
        let unanswered = TestWindow.new(id: 951, parent: fixture.spaces[0])
        unanswered.rectReader = {
            withUnsafeCurrentTask { $0?.cancel() }
            throw AXReadFailure(code: .cannotComplete)
        }

        do {
            try await runRefreshSessionBlocking(.ax(kAXWindowCreatedNotification as String))
            XCTFail("A cancelled session ran to the end")
        } catch is CancellationError {}
    }
}
