@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class WorkspaceSidebarGeometryTest: XCTestCase {
    func testCenteredSidebarUsesWindowRadiusAtBothWidthsAndOnBothEdges() {
        var configuration = WorkspaceSidebarConfiguration.empty
        configuration.heightMode = .centered
        let rect = CGRect(x: 0, y: 0, width: 240, height: 400)
        for side in WorkspaceSidebarPosition.allCases {
            configuration.position = side
            for width: CGFloat in [44, 240] {
                let shape = workspaceSidebarPanelShape(configuration: configuration, visibleWidth: width)
                XCTAssertEqual(shape.rightCornerRadius, systemWindowCornerRadius())
                XCTAssertTrue(shape.roundAllCorners)
                let path = shape.path(in: rect)
                for point in [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 239.9, y: 0.1),
                              CGPoint(x: 0.1, y: 399.9), CGPoint(x: 239.9, y: 399.9)] {
                    XCTAssertFalse(path.contains(point))
                }
                XCTAssertTrue(path.contains(CGPoint(x: 120, y: 200)))
            }
        }
        configuration.heightMode = .full
        let full = workspaceSidebarPanelShape(configuration: configuration, visibleWidth: 0)
        XCTAssertFalse(full.roundAllCorners)
        XCTAssertEqual(full.rightCornerRadius, 0)
    }

    func testHiddenOpeningStripAndExpandedExitToleranceUseSeparateRegionsOnBothEdges() {
        var config = WorkspaceSidebarConfig()
        config.autoHide = true
        config.collapsedWidth = 44
        config.width = 280
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: -300, width: 1920, height: 1080)]
        for screen in screens {
            for side in WorkspaceSidebarPosition.allCases {
                config.position = side
                let frame = workspaceSidebarPanelFrame(screen: screen, menuBarHeight: 38, config: config, contentHeight: 300)
                let width = workspaceSidebarHoverRegionWidth(config, visibleWidth: 0, isExpanded: false)
                XCTAssertEqual(width, 2)
                let region = workspaceSidebarVisibleFrame(panel: frame, width: width, position: side)
                func point(_ inset: CGFloat) -> CGPoint {
                    CGPoint(x: side == .left ? screen.minX + inset : screen.maxX - inset, y: frame.midY)
                }
                XCTAssertTrue(region.contains(point(1)))
                for inset: CGFloat in [-1, 3, 11, 44, 63] { XCTAssertFalse(region.contains(point(inset))) }
                let openWidth = workspaceSidebarHoverRegionWidth(config, visibleWidth: 280, isExpanded: true)
                XCTAssertEqual(openWidth, 300)
                let open = workspaceSidebarVisibleFrame(panel: frame, width: openWidth, position: side)
                XCTAssertTrue(open.contains(point(290)))
                XCTAssertFalse(open.contains(point(301)))
                // During collapse the flag can outlive the rendered width.
                XCTAssertEqual(workspaceSidebarHoverRegionWidth(config, visibleWidth: 0, isExpanded: true), 2)
            }
        }
        config.autoHide = false
        XCTAssertEqual(workspaceSidebarHoverRegionWidth(config, visibleWidth: 44, isExpanded: false), 44)
    }

    func testAutoHideUsesWholeNarrowStripWhileCompactRailKeepsDepthThreshold() {
        for origin: CGFloat in [-1920, 0, 1440] {
            XCTAssertTrue(isWorkspaceSidebarHoverDeepEnoughToExpand(mouseX: origin + 1.9,
                sidebarMinX: origin, collapsedWidth: 2, autoHide: true))
            XCTAssertFalse(isWorkspaceSidebarHoverDeepEnoughToExpand(mouseX: origin - 1,
                sidebarMinX: origin, collapsedWidth: 2, autoHide: true))
            XCTAssertFalse(isWorkspaceSidebarHoverDeepEnoughToExpand(mouseX: origin + 3,
                sidebarMinX: origin, collapsedWidth: 2, autoHide: true))
            XCTAssertTrue(isWorkspaceSidebarHoverDeepEnoughToExpand(mouseX: origin + 11,
                sidebarMinX: origin, collapsedWidth: 44))
            XCTAssertFalse(isWorkspaceSidebarHoverDeepEnoughToExpand(mouseX: origin + 12,
                sidebarMinX: origin, collapsedWidth: 44))
        }
    }

    func testRenderedMenuBoundsUseEachDisplaysOwnHeightWithoutWorkspaceClearance() {
        let notched = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let external = CGRect(x: -908, y: -1440, width: 3440, height: 1440)
        let bars = [CGRect(x: 0, y: 0, width: 1710, height: 38),
                    CGRect(x: -908, y: -1440, width: 3440, height: 24)]
        XCTAssertEqual(workspaceSidebarRenderedMenuBarHeight(screen: notched, safeAreaTop: 37.5, fallback: 39, menuBars: bars), 38)
        XCTAssertEqual(workspaceSidebarRenderedMenuBarHeight(screen: external, safeAreaTop: 0, fallback: 25, menuBars: bars), 24)
        XCTAssertEqual(workspaceSidebarRenderedMenuBarHeight(screen: notched, safeAreaTop: 37.5, fallback: 39, menuBars: [bars[1]]), 39)
        XCTAssertEqual(workspaceSidebarRenderedMenuBarHeight(screen: notched, safeAreaTop: 37.5, fallback: 39, menuBars: []), 39)
    }

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
