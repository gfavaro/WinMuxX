@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WindowWidthTest: WorkspaceTestCase {
    private func load(_ text: String) throws {
        let parsed = parseConfig(text)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        config.fullscreenWidth = parsed.config.fullscreenWidth
        config.singleWindowAlignment = parsed.config.singleWindowAlignment
        config.displayWindowSettings = parsed.config.displayWindowSettings
        config.workspaceLayouts = parsed.config.workspaceLayouts
    }

    func testRangeAndTypesAtEveryScope() {
        for prefix in ["", "[display.main]\n", "[workspace.1]\n", "[workspace.1.display.main]\n"] {
            for value in ["0", "0.09", "1.01", "nan", "inf", "-inf", "'0.7'", "true", "[]"] {
                XCTAssertFalse(parseConfig(prefix + "fullscreen-width = " + value).errors.isEmpty, prefix + value)
            }
            for value in ["0.1", "0.7", "1"] {
                XCTAssertTrue(parseConfig(prefix + "fullscreen-width = " + value).errors.isEmpty, prefix + value)
            }
            XCTAssertFalse(parseConfig(prefix + "single-window-alignment = 'top'").errors.isEmpty)
        }
        XCTAssertFalse(parseConfig("[display.main]\nfullscren-width = 0.7").errors.isEmpty)
        XCTAssertFalse(parseConfig("display = []").errors.isEmpty)
        XCTAssertFalse(parseConfig("[display.'']\nfullscreen-width = 0.7").errors.isEmpty)
    }

    func testPrecedenceAndDeterministicDisplaySelection() throws {
        let workspace = focus.workspace
        let name = workspace.name
        let screen = Rect(topLeftX: 0, topLeftY: 0, width: 1710, height: 1112)
        setMonitorsForTests([TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "Built-in Retina Display", rect: screen, visibleRect: screen, isMain: true)])
        try load("""
            fullscreen-width = 0.7
            single-window-alignment = 'left'
            [display.main]
            fullscreen-width = 0.9
            [display.'Built-in']
            fullscreen-width = 0.8
            [display.'Built-in Retina']
            fullscreen-width = 0.6
            single-window-alignment = 'right'
            """)
        XCTAssertEqual(workspace.windowWidthSettings.fullscreenWidth, 0.6)
        XCTAssertEqual(workspace.windowWidthSettings.singleWindowAlignment, .right)
        config.workspaceLayouts[name] = WorkspaceLayoutConfig(defaults: .init(fullscreenWidth: 0.5))
        XCTAssertEqual(workspace.windowWidthSettings.fullscreenWidth, 0.5)
        XCTAssertEqual(workspace.windowWidthSettings.singleWindowAlignment, .right)
        config.workspaceLayouts[name]?.displays = [WorkspaceDisplayLayout(selector: .main, settings: .init(singleWindowAlignment: .center))]
        XCTAssertEqual(workspace.windowWidthSettings.fullscreenWidth, 0.5)
        XCTAssertEqual(workspace.windowWidthSettings.singleWindowAlignment, .center)
        config.workspaceLayouts[name]?.displays[0] = WorkspaceDisplayLayout(selector: .main, settings: .init(fullscreenWidth: 1))
        XCTAssertEqual(workspace.windowWidthSettings.fullscreenWidth, 1)
        config.workspaceLayouts = [:]
        config.displayWindowSettings = []
        XCTAssertEqual(workspace.windowWidthSettings.fullscreenWidth, 0.7)
        XCTAssertEqual(workspace.windowWidthSettings.singleWindowAlignment, .left)
    }

    func testLoneWindowAlignmentMinimumsAndSecondWindowOnLaptop() async throws {
        try load("fullscreen-width = 0.7")
        let workspace = focus.workspace
        let window = TestWindow.new(id: 71001, parent: workspace.rootTilingContainer)
        let available = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        for (alignment, factor) in [(SingleWindowAlignment.left, 0.0), (.center, 0.5), (.right, 1.0)] {
            config.singleWindowAlignment = alignment
            try await workspace.layoutWorkspace()
            let frame = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
            XCTAssertEqual(frame.width, available.width * 0.7, accuracy: 0.001)
            XCTAssertEqual(frame.topLeftX, available.topLeftX + available.width * 0.3 * factor, accuracy: 0.001)
            XCTAssertEqual(dwindleGeometry(in: workspace)[ObjectIdentifier(window)]?.width, frame.width)
        }
        window.testMinimumSize = CGSize(width: available.width * 0.8, height: 0)
        XCTAssertEqual(workspaceTilingRect(workspace).width, available.width * 0.8, accuracy: 0.001)
        window.testMinimumSize = CGSize(width: available.width * 2, height: 0)
        XCTAssertEqual(workspaceTilingRect(workspace).width, available.width)
        window.testMinimumSize = .zero
        let floating = TestWindow.new(id: 71002, parent: workspace)
        XCTAssertTrue(floating.isFloating)
        XCTAssertEqual(workspaceTilingRect(workspace).width, available.width * 0.7, accuracy: 0.001)
        let second = TestWindow.new(id: 71003, parent: workspace.rootTilingContainer)
        XCTAssertEqual(workspaceTilingRect(workspace).width, available.width)
        second.unbindFromParent()
        XCTAssertEqual(workspaceTilingRect(workspace).width, available.width * 0.7, accuracy: 0.001)
    }

    func testFullscreenStaysCenteredAndHonorsNoOuterGaps() async throws {
        try load("fullscreen-width = 0.7\nsingle-window-alignment = 'right'")
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        _ = TestWindow.new(id: 72001, parent: root)
        let window = TestWindow.new(id: 72002, parent: root)
        window.markAsMostRecentChild()
        window.isFullscreen = true
        for noGaps in [false, true] {
            window.noOuterGapsInFullscreen = noGaps
            let monitor = workspace.workspaceMonitor
            let available = noGaps ? monitor.visibleRect : monitor.visibleRectPaddedByOuterGaps
            try await workspace.layoutWorkspace()
            let actual = try await window.getAxRect()
            let frame = try XCTUnwrap(actual)
            XCTAssertEqual(frame.width, available.width * 0.7, accuracy: 0.001)
            XCTAssertEqual(frame.topLeftX, available.topLeftX + available.width * 0.15, accuracy: 0.001)
            XCTAssertEqual(workspaceTilingRect(workspace), frame)
        }
        window.isFullscreen = false
        XCTAssertEqual(workspaceTilingRect(workspace), workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)
    }

    func testWidthPoliciesPreserveManualLayoutAndResizing() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let window = TestWindow.new(id: 73001, parent: root)
        workspace.applyConfiguredLayout()
        root.layout = .dwindle
        try load("[workspace.'\(workspace.name)']\nfullscreen-width = 0.7\nsingle-window-alignment = 'left'")
        workspace.applyConfiguredLayout()
        XCTAssertEqual(root.layout, .dwindle)
        XCTAssertTrue(applySingleWindowManualResize(window, width: 800))
        XCTAssertEqual(workspaceTilingRect(workspace).width, 800)
        window.singleWindowManualWidth = nil
        config.workspaceLayouts[workspace.name]?.defaults.fullscreenWidth = 0.6
        workspace.applyConfiguredLayout()
        XCTAssertEqual(root.layout, .dwindle)
        for layout in [Layout.tiles, .dwindle, .master, .tabGroup, .stacked] {
            root.layout = layout
            try await workspace.layoutWorkspace()
            XCTAssertEqual(workspaceTilingRect(workspace).width,
                           workspace.workspaceMonitor.visibleRectPaddedByOuterGaps.width * 0.6, accuracy: 0.001)
        }
    }
}
