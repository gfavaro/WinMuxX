@testable import AppBundle
import XCTest

@MainActor
final class VirtualFrameRecoveryTest: XCTestCase {
    private let tile = Rect(topLeftX: 100, topLeftY: 50, width: 800, height: 600)
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testAnAppThatKeepsMovingItsWindowIsLeftAloneUntilItRests() {
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = tile
        let recovery = VirtualFrameRecovery()
        var frame = CGRect(x: 400, y: 50, width: 800, height: 600)
        recovery.frame = { _ in frame }
        for _ in 0..<FrameRecoveryBudget.limit {
            XCTAssertTrue(recovery.shouldPutBack(window))
            recovery.settled(window.windowId)
        }
        XCTAssertFalse(recovery.shouldPutBack(window), "Three tries on the same tile, then the app wins")
        frame = CGRect(x: 100, y: 50, width: 800, height: 600)
        recovery.settled(window.windowId)
        XCTAssertTrue(recovery.shouldPutBack(window), "Coming to rest on the tile renews the budget")
    }

    func testANewTileOrRetileRenewsTheBudget() {
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = tile
        let recovery = VirtualFrameRecovery()
        recovery.frame = { _ in CGRect(x: 400, y: 50, width: 800, height: 600) }
        for _ in 0..<FrameRecoveryBudget.limit { recovery.settled(window.windowId) }
        XCTAssertFalse(recovery.shouldPutBack(window))
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 50, width: 900, height: 600)
        XCTAssertTrue(recovery.shouldPutBack(window), "A new tile")
        for _ in 0..<FrameRecoveryBudget.limit { recovery.settled(window.windowId) }
        XCTAssertFalse(recovery.shouldPutBack(window))
        recovery.reset()
        XCTAssertTrue(recovery.shouldPutBack(window), "retile")
    }

    func testFloatingWindowsAreNotLimited() {
        let window = TestWindow.new(id: 1, parent: focus.workspace)
        window.lastAppliedLayoutPhysicalRect = tile
        let recovery = VirtualFrameRecovery()
        recovery.frame = { _ in CGRect(x: 400, y: 50, width: 800, height: 600) }
        for _ in 0..<5 { recovery.settled(window.windowId) }
        XCTAssertTrue(recovery.shouldPutBack(window))
    }
}
