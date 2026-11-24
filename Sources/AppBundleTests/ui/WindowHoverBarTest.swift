@testable import AppBundle
import Common
import XCTest

@MainActor
final class WindowHoverBarTest: WorkspaceTestCase {
    func testZoneIsTheTopEdgeWithoutItsCorners() {
        let frame = Rect(topLeftX: 100, topLeftY: 50, width: 900, height: 600)
        let zone = WindowHoverBar.triggerZone(for: frame)
        XCTAssertEqual(zone.minX, 180)
        XCTAssertEqual(zone.width, 740)
        XCTAssertEqual(zone.minY, 47, "Reaches just above the edge, so the border itself counts")
        XCTAssertEqual(zone.height, 8, "Only the edge, not the whole title bar")
        let narrow = WindowHoverBar.triggerZone(for: Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 400))
        XCTAssertEqual(narrow.minX, 50, "Narrow windows keep a quarter at each corner")
        XCTAssertEqual(narrow.width, 100)
    }

    func testBarAppearsAtThePointerAndStaysInsideTheWindow() {
        let frame = Rect(topLeftX: 100, topLeftY: 50, width: 900, height: 600)
        let size = CGSize(width: 180, height: 26)
        let atPointer = WindowHoverBar.barFrame(for: frame, size: size, pointerX: 300)
        XCTAssertEqual(atPointer.minX + atPointer.width / 2, 300, accuracy: 0.01)
        XCTAssertGreaterThan(atPointer.minY, frame.minY)
        XCTAssertEqual(WindowHoverBar.barFrame(for: frame, size: size, pointerX: 105).minX, 104, "Kept inside the left edge")
        XCTAssertEqual(WindowHoverBar.barFrame(for: frame, size: size, pointerX: 995).maxX, 996, "Kept inside the right edge")
        let tight = WindowHoverBar.barFrame(for: Rect(topLeftX: 0, topLeftY: 0, width: 150, height: 300), size: size, pointerX: 75)
        XCTAssertEqual(tight.minX, 4, "A bar wider than the window starts at its left edge")
    }

    func testOffersMainOnlyInMasterAndTargetsTheWindow() async throws {
        let workspace = focus.workspace
        let a = TestWindow.new(id: 9601, parent: workspace.rootTilingContainer)
        _ = TestWindow.new(id: 9602, parent: workspace.rootTilingContainer)
        XCTAssertEqual(WindowHoverBar.actions(for: a).map(\.title), ["Focus", "Float", "Send to"])
        XCTAssertEqual(WindowHoverBar.actions(for: a).dropLast().map(\.command), ["fullscreen --window-id 9601", "layout floating tiling --window-id 9601"])
        workspace.arrangement = .master
        XCTAssertEqual(WindowHoverBar.actions(for: a).first?.command, "swap-with-master --window-id 9601")
        let floating = TestWindow.new(id: 9603, parent: workspace)
        XCTAssertEqual(WindowHoverBar.actions(for: floating).dropLast().map(\.command), ["layout tiling --window-id 9603"],
                       "A floated window offers Tile, so Float can be undone from the bar")
        for action in WindowHoverBar.actions(for: a) where action.choices.isEmpty {
            guard case .cmd = parseCommand(action.command) else { return XCTFail(action.command) }
        }
    }

    func testSendToListsTheWorkspacesAndTilesAFloatingWindowWhereItLands() async throws {
        let workspace = focus.workspace
        let tiled = TestWindow.new(id: 9621, parent: workspace.rootTilingContainer)
        let floating = TestWindow.new(id: 9622, parent: workspace)
        _ = TestWindow.new(id: 9623, parent: Workspace.get(byName: "send-target").rootTilingContainer)
        let tiledChoices = WindowHoverBar.sendToAction(for: tiled).choices.filter { !$0.isSeparator }
        let target = try XCTUnwrap(tiledChoices.first { $0.title == menuWorkspaceTitle(Workspace.get(byName: "send-target")) })
        XCTAssertEqual(target.commands, ["move-node-to-workspace --window-id 9621 \"send-target\""], "A tiled window is only moved")
        XCTAssertTrue(try XCTUnwrap(tiledChoices.first { $0.title == menuWorkspaceTitle(workspace) }).isCurrent, "Its own workspace is marked")
        let floatingTarget = try XCTUnwrap(WindowHoverBar.sendToAction(for: floating).choices
            .first { $0.title == menuWorkspaceTitle(Workspace.get(byName: "send-target")) })
        XCTAssertEqual(floatingTarget.commands, ["move-node-to-workspace --window-id 9622 \"send-target\"", "layout tiling --window-id 9622"],
                       "A floating window is tiled where it lands")
        for choice in WindowHoverBar.sendToAction(for: floating).choices where !choice.isSeparator {
            for command in choice.commands {
                guard case .cmd = parseCommand(command) else { return XCTFail(command) }
            }
        }
    }

    func testCandidateIsTheTiledWindowUnderTheTopEdge() async throws {
        let workspace = focus.workspace
        let a = TestWindow.new(id: 9611, parent: workspace.rootTilingContainer)
        let b = TestWindow.new(id: 9612, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let frameB = try XCTUnwrap(b.lastAppliedLayoutPhysicalRect)
        let zone = WindowHoverBar.triggerZone(for: frameB)
        XCTAssertEqual(WindowHoverBar.candidate(at: CGPoint(x: zone.minX + zone.width / 2, y: zone.minY + 2))?.windowId, b.windowId)
        XCTAssertNil(WindowHoverBar.candidate(at: CGPoint(x: zone.minX + zone.width / 2, y: frameB.minY + 200)), "Not the window body")
        XCTAssertNil(WindowHoverBar.candidate(at: CGPoint(x: frameB.minX + 2, y: frameB.minY + 2)), "Not the corners")
        // Focused: the bar on it offers Unfocus, and it wins over the tiles beneath it.
        b.isFullscreen = true
        try await workspace.layoutWorkspace()
        let full = try XCTUnwrap(WindowHoverBar.frame(of: b))
        let fullZone = WindowHoverBar.triggerZone(for: full)
        XCTAssertEqual(WindowHoverBar.candidate(at: CGPoint(x: fullZone.minX + fullZone.width / 2, y: fullZone.minY + 2))?.windowId, b.windowId)
        XCTAssertEqual(WindowHoverBar.actions(for: b).map(\.command), ["fullscreen off --window-id 9612"])
        _ = a
        XCTAssertFalse(parseConfig("[hover-bar]\nenabled = false").errors.isEmpty)
    }
}
