@testable import AppBundle
import XCTest

@MainActor
final class DesktopClickFocusTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testOnlyDesktopClicksOnAnotherWorkspaceRequestFocus() {
        let main = TestMonitor(
            monitorAppKitNsScreenScreensId: 1, name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 25, width: 1920, height: 1005),
            isMain: true,
        )
        let other = TestMonitor(
            monitorAppKitNsScreenScreensId: 2, name: "Other",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 25, width: 1920, height: 1005),
            isMain: false,
        )
        setMonitorsForTests([main, other])
        let current = Workspace.get(byName: "current")
        let destination = Workspace.get(byName: "destination")
        XCTAssertTrue(current.focusWorkspace())
        XCTAssertTrue(main.setActiveWorkspace(current))
        XCTAssertTrue(other.setActiveWorkspace(destination))

        XCTAssertTrue(GlobalObserver.desktopWorkspaceToFocus(at: CGPoint(x: 2000, y: 100)) === destination)
        XCTAssertNil(GlobalObserver.desktopWorkspaceToFocus(at: CGPoint(x: 2000, y: 10)), "Menu bar")
        XCTAssertNil(GlobalObserver.desktopWorkspaceToFocus(at: CGPoint(x: 2000, y: 1050)), "Dock")
        XCTAssertNil(GlobalObserver.desktopWorkspaceToFocus(at: CGPoint(x: 4000, y: 100)), "Outside both displays")
        XCTAssertNil(GlobalObserver.desktopWorkspaceToFocus(at: CGPoint(x: 100, y: 100)), "Current workspace")
        XCTAssertTrue(focus.workspace === current)
    }
}
