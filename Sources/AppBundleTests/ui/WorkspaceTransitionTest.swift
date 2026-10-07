@testable import AppBundle
import Foundation
import XCTest

@MainActor
final class WorkspaceTransitionTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testLastWindowClosureIgnoresTemporaryPromotionOfHiddenDocument() {
        let empty = Workspace.get(byName: "1")
        let hidden = Workspace.get(byName: "2")
        let document = TestWindow.new(id: 91001, parent: hidden.rootTilingContainer)
        _ = empty.focusWorkspace()
        let now = Date(timeIntervalSince1970: 100)
        holdFocusAfterLastWindowClosure(on: empty, appPid: document.app.pid, now: now)

        updateFocusCache(document, now: now.addingTimeInterval(0.1))
        XCTAssertTrue(focus.workspace === empty)
        XCTAssertNil(focus.windowOrNil)
        XCTAssertFalse(hidden.isVisible)

        updateFocusCache(document, now: now.addingTimeInterval(0.3))
        XCTAssertTrue(focus.workspace === hidden, "Normal native focus resumes after the closure settles")
        XCTAssertTrue(focus.windowOrNil === document)
    }

    func testExplicitWorkspaceChangeEndsLastWindowClosureHold() {
        let empty = Workspace.get(byName: "1")
        let destination = Workspace.get(byName: "2")
        let document = TestWindow.new(id: 91002, parent: destination.rootTilingContainer)
        _ = empty.focusWorkspace()
        let now = Date(timeIntervalSince1970: 100)
        holdFocusAfterLastWindowClosure(on: empty, appPid: document.app.pid, now: now)

        _ = destination.focusWorkspace()
        updateFocusCache(document, now: now.addingTimeInterval(0.1))
        XCTAssertTrue(focus.workspace === destination)
        XCTAssertTrue(focus.windowOrNil === document)
    }
}
