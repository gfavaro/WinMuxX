@testable import AppBundle
import Common
import XCTest

@MainActor
final class VirtualFrameRecoveryTest: XCTestCase {
    private let tile = Rect(topLeftX: 100, topLeftY: 50, width: 800, height: 600)
    private let moved = CGRect(x: 400, y: 50, width: 800, height: 600)
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func tiled() -> TestWindow {
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = tile
        return window
    }

    func testAnAppThatKeepsMovingItsWindowIsLeftAlone() {
        let window = tiled()
        let recovery = VirtualFrameRecovery()
        var frame = moved
        recovery.frame = { _ in frame }
        var putBacks = 0
        for _ in 0..<2 { recovery.settled(window.windowId) { putBacks += 1 } }
        frame = CGRect(x: 100, y: 50, width: 800, height: 600)
        recovery.settled(window.windowId) { putBacks += 1 }
        XCTAssertEqual(putBacks, 2, "Resting on the tile needs no put-back")
        frame = moved
        for _ in 0..<3 { recovery.settled(window.windowId) { putBacks += 1 } }
        XCTAssertEqual(putBacks, FrameRecoveryBudget.limit, "Three tries on the same tile, even with rests between, then the app wins")
    }

    func testANewTileOrRetileRenewsTheBudget() {
        let window = tiled()
        let recovery = VirtualFrameRecovery()
        recovery.frame = { [moved] _ in moved }
        var putBacks = 0
        for _ in 0..<4 { recovery.settled(window.windowId) { putBacks += 1 } }
        XCTAssertEqual(putBacks, FrameRecoveryBudget.limit)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 50, width: 900, height: 600)
        recovery.settled(window.windowId) { putBacks += 1 }
        XCTAssertEqual(putBacks, FrameRecoveryBudget.limit + 1, "A new tile")
        for _ in 0..<4 { recovery.settled(window.windowId) { putBacks += 1 } }
        recovery.reset()
        let before = putBacks
        recovery.settled(window.windowId) { putBacks += 1 }
        XCTAssertEqual(putBacks, before + 1, "retile")
    }

    func testLayoutLeavesAWindowAloneOnceItsTriesAreUsedUp() async throws {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        try await $refreshSessionEvent.withValue(.ax("test")) { try await workspace.layoutWorkspace() }
        let tile = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
        let away = CGPoint(x: tile.topLeftX + 300, y: tile.topLeftY)
        let recovery = VirtualFrameRecovery.shared
        defer { recovery.reset(); recovery.frame = windowServerFrame }
        recovery.frame = { _ in CGRect(origin: away, size: tile.size) }
        window.setAxFrame(away, nil) // Its app moves it.
        for _ in 0..<FrameRecoveryBudget.limit { recovery.settled(window.windowId) {} }
        // Another event's layout pass, which writes every window.
        try await $refreshSessionEvent.withValue(.ax("test")) { try await workspace.layoutWorkspace() }
        let leftAt = try await window.getAxRect()?.topLeftCorner
        XCTAssertEqual(leftAt, away, "Left where its app put it")
        recovery.reset() // retile
        try await $refreshSessionEvent.withValue(.ax("test")) { try await workspace.layoutWorkspace() }
        let backAt = try await window.getAxRect()?.topLeftCorner
        XCTAssertEqual(backAt, tile.topLeftCorner, "retile puts it back")
    }

    func testWindowsWithoutATileRefreshAtOnce() {
        let window = TestWindow.new(id: 1, parent: focus.workspace)
        let recovery = VirtualFrameRecovery()
        var putBacks = 0
        for _ in 0..<5 { recovery.windowChanged(window) { putBacks += 1 } }
        XCTAssertEqual(putBacks, 5)
    }
}
