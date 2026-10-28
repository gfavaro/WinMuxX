@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class NativeFocusHoldTest: XCTestCase {
    func testOnlyAwayActivationsAreRejectedAndTheHeldWindowReturnsOnceUntilExpiry() {
        setUpWorkspacesForTests()
        let home = TestWindow.new(id: 2001, parent: focus.workspace.rootTilingContainer)
        let nearby = TestWindow.new(id: 2002, parent: focus.workspace.rootTilingContainer)
        let away = TestWindow.new(id: 2003, parent: Workspace.get(byName: "away-desktop").rootTilingContainer)
        _ = home.focusWindow()
        var clock = ContinuousClock.now
        let hold = NativeFocusHold()
        hold.now = { clock }
        let displayOf: (Window) -> String? = { $0 === away ? "other" : "home" }

        XCTAssertFalse(hold.rejects(away, display: displayOf), "No hold, no rejection")
        hold.begin(window: home, homeDisplay: "home")
        XCTAssertFalse(hold.rejects(nearby, display: displayOf), "Focus may move on the home display")
        XCTAssertTrue(hold.rejects(away, display: displayOf))
        XCTAssertTrue(focus.windowOrNil === home)
        hold.settle(after: .milliseconds(500))
        clock += .milliseconds(400)
        XCTAssertTrue(hold.rejects(away, display: displayOf))
        clock += .milliseconds(200)
        XCTAssertFalse(hold.rejects(away, display: displayOf), "Expired")
        XCTAssertFalse(hold.isActive)

        hold.begin(window: home, homeDisplay: "home")
        hold.end()
        XCTAssertFalse(hold.rejects(away, display: displayOf), "A click elsewhere ends it")
    }
}
