@testable import AppBundle
import AppKit
import Common
import PrivateApi
import XCTest

@MainActor
final class WindowTabGroupBorderTest: WorkspaceTestCase {
    private func group() -> (TilingContainer, TestWindow, TestWindow) {
        config.windowTabs.enabled = true
        let group = TilingContainer(parent: Workspace.get(byName: "a").rootTilingContainer,
            adaptiveWeight: 1, .v, .tabGroup, index: INDEX_BIND_LAST)
        let first = TestWindow.new(id: 1, parent: group)
        let second = TestWindow.new(id: 2, parent: group)
        _ = first.focusWindow()
        return (group, first, second)
    }

    func testBorderEnclosesChromeAndTracksLiveMovementAndResize() throws {
        let (_, active, _) = group()
        config.windowTabs.height = 42
        for frame in [CGRect(x: 103, y: 242, width: 800, height: 600),
                      CGRect(x: -900, y: -700, width: 1200, height: 850)] {
            let target = try XCTUnwrap(windowBorderTarget(for: active, nativeFrame: frame))
            XCTAssertEqual(target.frame, CGRect(x: frame.minX - 3, y: frame.minY - 42,
                width: frame.width + 6, height: frame.height + 45))
            XCTAssertEqual(target.corners.top, windowTabStripCornerRadius)
            XCTAssertEqual(target.corners.bottom,
                windowTabGroupAppCornerRadius(activeWindowId: active.windowId) + 3)
        }
    }

    func testOnlyNewActiveTabOwnsTheOutlineDuringSwitch() throws {
        let (_, first, second) = group()
        let frame = CGRect(x: 50, y: 100, width: 700, height: 500)
        XCTAssertNotNil(windowBorderTarget(for: first, nativeFrame: frame))
        XCTAssertNil(windowBorderTarget(for: second, nativeFrame: frame))
        _ = second.focusWindow()
        XCTAssertNil(windowBorderTarget(for: first, nativeFrame: frame))
        XCTAssertNotNil(windowBorderTarget(for: second, nativeFrame: frame))
    }

    func testHiddenChromeDisabledTabsAndDissolvedGroupUseWindowFrame() throws {
        let (group, first, second) = group()
        let panels = WindowTabStripPanelController.shared
        defer { panels.mouseInteractionChromeMode = nil; panels.hiddenPassiveTabGroupChromeIds.removeAll() }
        let frame = CGRect(x: 50, y: 100, width: 700, height: 500)
        panels.mouseInteractionChromeMode = .hidden
        XCTAssertEqual(windowBorderTarget(for: first, nativeFrame: frame)?.frame, frame)
        panels.mouseInteractionChromeMode = .frameOnly
        XCTAssertNotEqual(windowBorderTarget(for: first, nativeFrame: frame)?.frame, frame)
        panels.mouseInteractionChromeMode = nil
        panels.hiddenPassiveTabGroupChromeIds = [ObjectIdentifier(group)]
        XCTAssertEqual(windowBorderTarget(for: first, nativeFrame: frame)?.frame, frame)
        panels.hiddenPassiveTabGroupChromeIds.removeAll()
        config.windowTabs.enabled = false
        XCTAssertEqual(windowBorderTarget(for: first, nativeFrame: frame)?.frame, frame)
        config.windowTabs.enabled = true
        second.unbindFromParent()
        XCTAssertEqual(windowBorderTarget(for: first, nativeFrame: frame)?.frame, frame)
    }

    func testTabContainingASplitUsesTheWholeGroupFrame() throws {
        config.windowTabs.enabled = true
        let group = TilingContainer(parent: Workspace.get(byName: "a").rootTilingContainer,
            adaptiveWeight: 1, .v, .tabGroup, index: INDEX_BIND_LAST)
        let split = TilingContainer(parent: group, adaptiveWeight: 1, .h, .tiles, index: INDEX_BIND_LAST)
        let first = TestWindow.new(id: 10, parent: split)
        let second = TestWindow.new(id: 11, parent: split)
        _ = TestWindow.new(id: 12, parent: group)
        group.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 100, topLeftY: 200, width: 1200, height: 800)
        _ = first.focusWindow()
        let target = try XCTUnwrap(windowBorderTarget(for: first,
            nativeFrame: CGRect(x: 103, y: 236, width: 597, height: 761)))
        XCTAssertEqual(target.frame, CGRect(x: 100, y: 200, width: 1200, height: 800))
        XCTAssertNil(windowBorderTarget(for: second, nativeFrame: .zero))
    }

    func testFallbackUsesTopLeftPiecesAndFlippedDrawingForUnevenCorners() throws {
        let border = WindowBorder(target: 0, createNativeBorder: { _, _ in false })
        defer { border.destroy() }
        let frame = CGRect(x: -20000, y: -20000, width: 800, height: 600)
        var settings = WindowBordersConfig()
        settings.width = 4
        border.update(frame: frame, active: true, settings: settings, corners: .init(top: 12, bottom: 19))
        let outer = CGRect(x: frame.minX, y: mainMonitor.height - frame.maxY,
            width: frame.width, height: frame.height).insetBy(dx: -4, dy: -4)
        for (index, id) in border.windowIds.enumerated() {
            let panel = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == Int(id) })
            let piece = winmux_border_piece(outer.size, 19, 4, 2, Int32(index))
            // Offscreen NSWindows can be attached to a 1x screen and snap a
            // half-point edge, even when the target's backing scale is 2x.
            let tolerance = 1 / panel.backingScaleFactor
            XCTAssertEqual(panel.frame.minX, outer.minX + piece.minX, accuracy: tolerance)
            XCTAssertEqual(panel.frame.minY, outer.maxY - piece.maxY, accuracy: tolerance)
            XCTAssertEqual(panel.frame.width, piece.width, accuracy: tolerance)
            XCTAssertEqual(panel.frame.height, piece.height, accuracy: tolerance)
            XCTAssertEqual(panel.contentView?.isFlipped, true)
        }
    }
}
