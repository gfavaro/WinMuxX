@testable import AppBundle
import Common
import XCTest

@MainActor
final class RetileCommandTest: WorkspaceTestCase {
    func testCountsOnlyTiledWindowsOffTheirTiles() async throws {
        let workspace = focus.workspace
        let windows = (0..<3).map { TestWindow.new(id: UInt32(9700 + $0), parent: workspace.rootTilingContainer) }
        let floating = TestWindow.new(id: 9710, parent: workspace)
        try await workspace.layoutWorkspace()
        let tiles = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowId, try! XCTUnwrap($0.lastAppliedLayoutPhysicalRect)) })
        var frames: [UInt32: CGRect] = tiles.mapValues { CGRect(x: $0.topLeftX, y: $0.topLeftY, width: $0.width, height: $0.height) }
        frames[floating.windowId] = CGRect(x: 900, y: 900, width: 10, height: 10)
        XCTAssertTrue(retileCandidates(frame: { frames[$0] }).isEmpty, "Every tile is in place")

        frames[9701] = frames[9701]!.offsetBy(dx: 60, dy: 0)
        frames[9702] = CGRect(origin: frames[9702]!.origin, size: CGSize(width: 50, height: 50))
        frames[9700] = CGRect(origin: frames[9700]!.origin, size: CGSize(width: frames[9700]!.width + 40, height: frames[9700]!.height))
        XCTAssertEqual(retileCandidates(frame: { frames[$0] }).map(\.windowId).sorted(), [9701, 9702],
                       "A moved or shrunk window counts; one larger than its tile (an app that cannot shrink) does not")
    }

    func testForgetsTheTilesOfMovedWindowsSoTheLayoutPassWritesThem() async throws {
        let workspace = focus.workspace
        let moved = TestWindow.new(id: 9720, parent: workspace.rootTilingContainer)
        let resting = TestWindow.new(id: 9721, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let tile = try XCTUnwrap(resting.lastAppliedLayoutPhysicalRect)
        let restingFrame = CGRect(x: tile.topLeftX, y: tile.topLeftY, width: tile.width, height: tile.height)
        RetileCommand.frame = { $0 == moved.windowId ? CGRect(x: 5000, y: 5000, width: 10, height: 10) : restingFrame }
        defer { RetileCommand.frame = windowServerFrame }
        let result = try await XCTUnwrap(parseCommand("retile").unwrap().0).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.stdout, ["Put 1 window back"])
        // A command's layout pass reuses an unchanged tile without writing; a forgotten one is written.
        XCTAssertNil(moved.lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(resting.lastAppliedLayoutPhysicalRect, tile)
    }

    func testReportsTheCountAndShowsANotice() async throws {
        let result = try await XCTUnwrap(parseCommand("retile").unwrap().0).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, ["Nothing had moved"])
        XCTAssertEqual(NoticePanel.shared.lastNotice?.body, "Nothing had moved")
    }
}
