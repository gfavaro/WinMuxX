@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WindowTabPillRailTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func model(_ id: ObjectIdentifier, active: UInt32, shown: Set<UInt32>) -> WindowTabStripViewModel {
        let tabs = [1, 2, 3].map { windowId in
            WindowTabItemViewModel(windowId: UInt32(windowId), workspaceName: "a", appName: "App", appBundleId: nil,
                appBundlePath: nil, title: "\(windowId)", isActive: UInt32(windowId) == active)
        }
        let group = CGRect(x: 100, y: mainMonitor.height - 400, width: 600, height: 300)
        return WindowTabStripViewModel(id: id, workspaceName: "a", frame: windowTabBarFrame(fromGroupFrame: group),
            groupFrame: group, activeWindowId: active, activeWindowCornerRadius: 10, tabs: tabs,
            occludingFloatingWindowFrames: [], shownWindowIds: shown, railHeight: windowTabPillRailHeight)
    }

    func testRailZoneIsTheGroupsTopEdgeInTopLeftCoordinates() {
        let group = CGRect(x: 100, y: mainMonitor.height - 400, width: 600, height: 300)
        let zone = WindowTabRailHover.railZone(groupFrame: group, railHeight: windowTabPillRailHeight)
        XCTAssertEqual(zone.minY, 100 - WindowTabRailHover.slack)
        XCTAssertEqual(zone.height, windowTabPillRailHeight + 2 * WindowTabRailHover.slack)
        XCTAssertTrue(zone.contains(CGPoint(x: 300, y: 106)), "The middle of the rail opens the strip")
        XCTAssertFalse(zone.contains(CGPoint(x: 300, y: 140)), "The window body below the rail does not")
    }

    func testTabSwitchShowsTheStripBrieflyButAStripColumnDoesNot() {
        let controller = WindowTabStripPanelController.shared
        let tabs = TilingContainer(parent: Workspace.get(byName: name).rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let strip = TilingContainer(parent: Workspace.get(byName: name).rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 1)
        let tabsId = ObjectIdentifier(tabs), stripId = ObjectIdentifier(strip)
        defer { controller.flashExpandedId = nil; controller.hoverExpandedId = nil }
        controller.noteActiveTabs([model(tabsId, active: 1, shown: [1]), model(stripId, active: 1, shown: [1, 2])])
        XCTAssertNil(controller.flashExpandedId, "The first sighting is not a switch")

        controller.noteActiveTabs([model(tabsId, active: 1, shown: [1]), model(stripId, active: 2, shown: [1, 2])])
        XCTAssertNil(controller.flashExpandedId, "A strip's columns stay on screen, so its rail is enough")

        controller.noteActiveTabs([model(tabsId, active: 3, shown: [3]), model(stripId, active: 2, shown: [1, 2])])
        XCTAssertEqual(controller.flashExpandedId, tabsId, "A hidden tab coming forward names itself")
        XCTAssertTrue(controller.isExpanded(tabsId))

        controller.hoverExpandedId = stripId
        XCTAssertTrue(controller.isExpanded(stripId), "Hovering the rail keeps a group open")
    }

    func testCopiesKeepTheRailState() {
        let id = ObjectIdentifier(Workspace.get(byName: name))
        let original = model(id, active: 2, shown: [1, 2]).expanded(true)
        let aligned = original.alignedForWindowTabChrome()
        XCTAssertEqual(aligned.shownWindowIds, [1, 2])
        XCTAssertEqual(aligned.railHeight, windowTabPillRailHeight)
        XCTAssertTrue(aligned.isExpanded)
        XCTAssertNotEqual(WindowTabGroupChromeContent(strip: original), WindowTabGroupChromeContent(strip: original.expanded(false)),
            "Opening or closing the strip redraws the rail")
    }

    func testStripLayoutRecordsItsVisibleColumnsForThePills() async throws {
        let workspace = Workspace.get(byName: name)
        let strip = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        strip.presentsAsStrip = true
        let first = TestWindow.new(id: 8201, parent: strip)
        _ = TestWindow.new(id: 8202, parent: strip)
        _ = TestWindow.new(id: 8203, parent: strip)
        first.markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(strip.stripVisibleColumns, 0 ..< 2)
    }
}
