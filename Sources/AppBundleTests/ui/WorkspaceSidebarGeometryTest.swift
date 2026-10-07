@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class WorkspaceSidebarGeometryTest: XCTestCase {
    func testEveryModeAndSideProtectsMenuBarAndAnchorsToDisplayEdge() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -300, width: 1920, height: 1080)]
        for screen in screens {
            for side in WorkspaceSidebarPosition.allCases {
                for mode in WorkspaceSidebarHeightMode.allCases {
                    var config = WorkspaceSidebarConfig()
                    config.position = side
                    config.heightMode = mode
                    config.menuBarReserveHeight = 0
                    let frame = workspaceSidebarPanelFrame(screen: screen, menuBarHeight: 38, config: config, contentHeight: 300)
                    XCTAssertLessThanOrEqual(frame.maxY, screen.maxY - 38)
                    XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
                    XCTAssertEqual(side == .left ? frame.minX : frame.maxX, side == .left ? screen.minX : screen.maxX)
                    for width in [CGFloat(0), 44, 240, 480] {
                        let visible = workspaceSidebarVisibleFrame(panel: frame, width: width, position: side)
                        XCTAssertEqual(side == .left ? visible.minX : visible.maxX, side == .left ? screen.minX : screen.maxX)
                        XCTAssertEqual(visible.width, width)
                    }
                }
            }
        }
    }

    func testCenteredFitsContentGrowsBeyondSixtyPercentAndCapsAtNinety() {
        var config = WorkspaceSidebarConfig()
        config.heightMode = .centered
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 1028)
        for (content, expected) in [(200.0, 200.0), (700.0, 700.0), (2000.0, 900.0)] {
            let frame = workspaceSidebarPanelFrame(screen: screen, menuBarHeight: 28, config: config, contentHeight: content)
            XCTAssertEqual(frame.height, expected)
            XCTAssertEqual(frame.midY, 500)
        }
    }

    func testLegacyClearanceCannotOverlapMenuBarAndNewModeOverridesIt() {
        var config = WorkspaceSidebarConfig()
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
        config.menuBarReserveHeight = 0
        XCTAssertEqual(workspaceSidebarPanelFrame(screen: screen, menuBarHeight: 38, config: config, contentHeight: 0).maxY, 862)
        config.menuBarReserveHeight = 72
        XCTAssertEqual(workspaceSidebarPanelFrame(screen: screen, menuBarHeight: 38, config: config, contentHeight: 0).maxY, 828)
        config.heightMode = .full
        XCTAssertEqual(workspaceSidebarPanelFrame(screen: screen, menuBarHeight: 38, config: config, contentHeight: 0).maxY, 862)
    }

    func testIdleBackingShrinksAndTransitionsPreserveBrowsingCanvas() {
        var config = WorkspaceSidebarConfig()
        config.width = 240
        config.alwaysExpanded = false
        let resting = workspaceSidebarRestingWidth(config)
        let idle = workspaceSidebarBackingWidth(config: config, visibleWidth: resting, isExpanded: false, isAnimating: false)
        XCTAssertLessThan(idle, 480)
        XCTAssertGreaterThanOrEqual(idle, workspaceSidebarHoverActivationWidth(config))
        for (expanded, animating, width) in [(true, false, resting), (false, true, resting), (false, false, CGFloat(240))] {
            XCTAssertEqual(workspaceSidebarBackingWidth(config: config, visibleWidth: width, isExpanded: expanded, isAnimating: animating), 480)
        }
        let screen = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        for side in WorkspaceSidebarPosition.allCases {
            config.position = side
            let frame = workspaceSidebarPanelFrame(screen: screen, menuBarHeight: 38, config: config, contentHeight: 300, backingWidth: idle)
            XCTAssertEqual(frame.width, idle)
            XCTAssertEqual(side == .left ? frame.minX : frame.maxX, side == .left ? screen.minX : screen.maxX)
        }
    }

    func testGeometryOptionsParseAndRejectInvalidValues() {
        for position in WorkspaceSidebarPosition.allCases {
            for mode in WorkspaceSidebarHeightMode.allCases {
                let (parsed, errors) = parseConfig("[workspace-sidebar]\nposition = '\(position.rawValue)'\nheight-mode = '\(mode.rawValue)'\n")
                XCTAssertTrue(errors.isEmpty)
                XCTAssertEqual(parsed.workspaceSidebar.position, position)
                XCTAssertEqual(parsed.workspaceSidebar.heightMode, mode)
            }
        }
        let (legacy, errors) = parseConfig("[workspace-sidebar]\nmenu-bar-reserve-height = 0\n")
        XCTAssertTrue(errors.isEmpty)
        XCTAssertNil(legacy.workspaceSidebar.heightMode)
        XCTAssertEqual(legacy.workspaceSidebar.position, .left)
        for entry in ["position = 'top'", "height-mode = 'huge'"] {
            XCTAssertFalse(parseConfig("[workspace-sidebar]\n\(entry)\n").1.isEmpty)
        }
    }
}
