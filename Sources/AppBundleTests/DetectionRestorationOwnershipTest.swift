@testable import AppBundle
import XCTest

final class DetectionRestorationOwnershipTest: XCTestCase {
    @MainActor
    func testDetectionCommitRemainsValidForCurrentWindow() throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        let window = TestWindow.new(id: 7001, parent: focus.workspace.rootTilingContainer)
        let commit = DetectionCommit(window, isCurrent: { $0 === window })
        XCTAssertNoThrow(try commit.check())
    }

    @MainActor
    func testDetectionCommitRejectsReplacedWindowAfterSuspension() throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        let original = TestWindow.new(id: 7002, parent: focus.workspace.rootTilingContainer)
        let replacement = TestWindow.new(id: 7003, parent: focus.workspace.rootTilingContainer)
        var current: Window = original
        let commit = DetectionCommit(original, isCurrent: { $0 === current })

        XCTAssertNoThrow(try commit.check())
        // Simulates the owner changing while an AX/restoration await is suspended.
        current = replacement
        XCTAssertThrowsError(try commit.check()) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }
}
