@testable import AppBundle
import Common
import XCTest

@MainActor
final class WindowHoverBarTest: WorkspaceTestCase {
    func testZoneIsTheMiddleOfTheTopEdgeAndTheBarSitsInsideIt() {
        let frame = Rect(topLeftX: 100, topLeftY: 50, width: 900, height: 600)
        let zone = WindowHoverBar.triggerZone(for: frame)
        XCTAssertEqual(zone.minX, 400)
        XCTAssertEqual(zone.width, 300)
        XCTAssertEqual(zone.minY, 50)
        XCTAssertEqual(zone.height, WindowHoverBar.zoneHeight)
        XCTAssertEqual(WindowHoverBar.triggerZone(for: Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 400)).width, 120,
                       "Narrow windows keep a usable target")
        let bar = WindowHoverBar.barFrame(for: frame, size: CGSize(width: 180, height: 26))
        XCTAssertEqual(bar.minX + bar.width / 2, frame.minX + frame.width / 2, accuracy: 0.01)
        XCTAssertGreaterThan(bar.minY, frame.minY)
    }

    func testOffersMainOnlyInMasterAndTargetsTheWindow() async throws {
        let workspace = focus.workspace
        let a = TestWindow.new(id: 9601, parent: workspace.rootTilingContainer)
        _ = TestWindow.new(id: 9602, parent: workspace.rootTilingContainer)
        XCTAssertEqual(WindowHoverBar.actions(for: a).map(\.title), ["Focus", "Float"])
        XCTAssertEqual(WindowHoverBar.actions(for: a).map(\.command), ["fullscreen --window-id 9601", "layout floating tiling --window-id 9601"])
        workspace.arrangement = .master
        XCTAssertEqual(WindowHoverBar.actions(for: a).first?.command, "swap-with-master --window-id 9601")
        for action in WindowHoverBar.actions(for: a) {
            guard case .cmd = parseCommand(action.command) else { return XCTFail(action.command) }
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
        _ = a
        XCTAssertTrue(parseConfig("").config.hoverBar.enabled)
        XCTAssertFalse(parseConfig("[hover-bar]\nenabled = false").config.hoverBar.enabled)
    }
}
