@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class SingleWindowGeometryTest: XCTestCase {
    func testScreenThresholdAndOrientation() {
        let available = Rect(topLeftX: 130, topLeftY: 40, width: 3000, height: 1001)
        for (width, height, limited) in [(1920.0, 1080.0, false), (2300, 1000, true), (2299, 1000, false), (3440, 1440, true), (5120, 1440, true), (1440, 3440, false)] {
            let result = singleWindowLimitedRect(available: available, screen: Rect(topLeftX: 0, topLeftY: 0, width: width, height: height), ratio: 1.5, minimumWidth: 0)
            XCTAssertEqual(result.width, limited ? 1500 : 3000)
            XCTAssertEqual(result.topLeftX, limited ? 880 : 130)
            XCTAssertEqual(result.height, 1001)
            XCTAssertEqual(result.topLeftY, 40)
        }
    }

    func testDisabledNarrowAreaAndMinimums() {
        let screen = Rect(topLeftX: 0, topLeftY: 0, width: 3440, height: 1440)
        let available = Rect(topLeftX: 100, topLeftY: 30, width: 3000, height: 1001)
        for (ratio, minimum, expected) in [(0.0, 0.0, 3000.0), (1.5, 1800, 1800), (1.5, 4000, 3000)] {
            XCTAssertEqual(singleWindowLimitedRect(available: available, screen: screen, ratio: ratio, minimumWidth: minimum).width, expected)
        }
        XCTAssertEqual(singleWindowLimitedRect(available: available.copy(\.width, 900), screen: screen, ratio: 1.5, minimumWidth: 0).width, 900)
    }

    func testEligibilityTransitionsAndSharedGeometry() async throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        let screen = Rect(topLeftX: 0, topLeftY: 0, width: 3440, height: 1440)
        setMonitorsForTests([TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "S34CG50", rect: screen, visibleRect: screen, isMain: true)])
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let window = TestWindow.new(id: 1001, parent: root)
        let fullWidth = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps.width
        let limited = workspaceTilingRect(workspace)
        XCTAssertLessThan(limited.width, screen.width)
        try await workspace.layoutWorkspace()
        XCTAssertEqual(window.lastAppliedLayoutPhysicalRect?.width, limited.width)
        XCTAssertEqual(dwindleGeometry(in: workspace)[ObjectIdentifier(window)]?.width, limited.width)
        let preview = windowResizePreviewItems(in: workspace, weightMap: .init(), excludingActiveWindowId: nil)
        XCTAssertEqual(preview.first?.frame, window.lastAppliedLayoutPhysicalRect?.toAppKitScreenRect.alignedToBackingPixels())
        window.testMinimumSize = CGSize(width: limited.width + 100, height: 0)
        XCTAssertEqual(workspaceTilingRect(workspace).width, limited.width + 100)
        window.testMinimumSize = .zero
        let second = TestWindow.new(id: 1002, parent: root)
        XCTAssertEqual(workspaceTilingRect(workspace).width, fullWidth)
        second.unbindFromParent()
        XCTAssertEqual(workspaceTilingRect(workspace).width, limited.width)
        let floating = TestWindow.new(id: 1003, parent: workspace)
        XCTAssertEqual(workspaceTilingRect(workspace).width, fullWidth)
        floating.unbindFromParent()
        _ = TestWindow.new(id: 1004, parent: workspace.macOsNativeHiddenAppsWindowsContainer)
        XCTAssertEqual(workspaceTilingRect(workspace).width, limited.width)
        config.singleWindowAspectRatio = parseConfig("single-window-aspect-ratio = [{ monitor.\"S34CG50\" = 0 }, 1.5]").config.singleWindowAspectRatio
        XCTAssertEqual(workspaceTilingRect(workspace).width, fullWidth)
        config.singleWindowAspectRatio = .constant(1.5)
        window.isFullscreen = true
        XCTAssertEqual(workspaceTilingRect(workspace).width, fullWidth)
        window.isFullscreen = false
        root.layout = .tabGroup
        XCTAssertEqual(workspaceTilingRect(workspace).width, fullWidth)
        _ = TestWindow.new(id: 1005, parent: root)
        XCTAssertEqual(workspaceTilingRect(workspace).width, fullWidth)
    }

    func testManualResizePersistsAcrossRefreshAndSingleWindowTransitions() async throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        let screen = Rect(topLeftX: 0, topLeftY: 0, width: 3440, height: 1440)
        setMonitorsForTests([TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "wide", rect: screen, visibleRect: screen, isMain: true)])
        let workspace = focus.workspace
        let window = TestWindow.new(id: 2001, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let initial = workspaceTilingRect(workspace)
        applyResizeWithMouse(window, rect: initial.copy(\.width, 2600))
        cancelManipulatedWithMouseState()
        for alignment in SingleWindowAlignment.allCases {
            config.singleWindowAlignment = alignment
            try await workspace.layoutWorkspace()
            let rect = workspaceTilingRect(workspace)
            XCTAssertEqual(rect.width, 2600)
            XCTAssertEqual(rect.height, initial.height)
            let preview = windowResizePreviewItems(in: workspace, weightMap: .init(), excludingActiveWindowId: nil)
            XCTAssertEqual(preview.first?.frame, window.lastAppliedLayoutPhysicalRect?.toAppKitScreenRect.alignedToBackingPixels())
        }
        let second = TestWindow.new(id: 2002, parent: workspace.rootTilingContainer)
        XCTAssertEqual(workspaceTilingRect(workspace).width, workspace.workspaceMonitor.visibleRectPaddedByOuterGaps.width)
        XCTAssertFalse(applySingleWindowManualResize(window, width: 1700))
        second.unbindFromParent()
        XCTAssertEqual(workspaceTilingRect(workspace).width, 2600)
        _ = window.focusWindow()
        let command = try await parseCommand("resize width +100").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(command.exitCode, 0)
        XCTAssertEqual(workspaceTilingRect(workspace).width, 2700)
        window.testMinimumSize = CGSize(width: 2800, height: 0)
        XCTAssertEqual(workspaceTilingRect(workspace).width, 2800)
        window.testMinimumSize = .zero
        XCTAssertFalse(applySingleWindowManualResize(window, width: .nan))
        XCTAssertTrue(applySingleWindowManualResize(window, width: 9000))
        XCTAssertEqual(workspaceTilingRect(workspace).width, workspace.workspaceMonitor.visibleRectPaddedByOuterGaps.width)
        config.singleWindowAspectRatio = .constant(0)
        XCTAssertFalse(applySingleWindowManualResize(window, width: 1000))
    }

    func testHeightResizeFloatsAndPreservesGestureFrame() async throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        let screen = Rect(topLeftX: 0, topLeftY: 0, width: 3440, height: 1440)
        setMonitorsForTests([TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "wide", rect: screen, visibleRect: screen, isMain: true)])
        let workspace = focus.workspace
        let window = TestWindow.new(id: 3001, parent: workspace.rootTilingContainer)
        try await workspace.layoutWorkspace()
        let original = window.lastAppliedLayoutPhysicalRect!
        XCTAssertFalse(floatSingleWindowAfterHeightResize(window, rect: original.copy(\.height, original.height - 1)))
        let resized = Rect(topLeftX: original.topLeftX + 30, topLeftY: original.topLeftY + 40, width: 1700, height: 800)
        applyResizeWithMouse(window, rect: resized)
        cancelManipulatedWithMouseState()
        XCTAssertTrue(window.isFloating)
        XCTAssertTrue(window.parent === workspace)
        XCTAssertEqual(window.lastFloatingSize, resized.size)
        let observed = try await window.getAxRect()
        XCTAssertEqual(observed, resized)
        XCTAssertNil(window.lastAppliedLayoutPhysicalRect)
        XCTAssertNil(window.lastAppliedLayoutVirtualRect)
        try await workspace.layoutWorkspace()
        let refreshed = try await window.getAxRect()
        XCTAssertEqual(refreshed, resized)
    }

    func testHeightResizeDoesNotFloatMultiWindowLayout() async throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        let screen = Rect(topLeftX: 0, topLeftY: 0, width: 3440, height: 1440)
        setMonitorsForTests([TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "wide", rect: screen, visibleRect: screen, isMain: true)])
        let root = focus.workspace.rootTilingContainer
        let window = TestWindow.new(id: 3002, parent: root)
        _ = TestWindow.new(id: 3003, parent: root)
        try await focus.workspace.layoutWorkspace()
        let resized = window.lastAppliedLayoutPhysicalRect!.copy(\.height, 400)
        XCTAssertFalse(floatSingleWindowAfterHeightResize(window, rect: resized))
        XCTAssertFalse(window.isFloating)
    }

    func testAlignmentAndParsing() {
        let available = Rect(topLeftX: 150, topLeftY: 20, width: 3000, height: 1001)
        for (alignment, expectedX) in [(SingleWindowAlignment.left, 150.0), (.center, 900.0), (.right, 1650.0)] {
            let rect = alignedSingleWindowRect(available: available, width: 1500, minimumWidth: 0, alignment: alignment)
            XCTAssertEqual(rect.topLeftX, expectedX)
            XCTAssertEqual(rect.height, available.height)
            let parsed = parseConfig("single-window-alignment = '\(alignment.rawValue)'")
            XCTAssertTrue(parsed.errors.isEmpty)
            XCTAssertEqual(parsed.config.singleWindowAlignment, alignment)
        }
        XCTAssertFalse(parseConfig("single-window-alignment = 'bottom'").errors.isEmpty)
    }

    func testParsingAndPersistence() {
        for value in ["0", "1", "1.5", "[{ monitor.\"Disconnected\" = 2 }, 1.5]"] {
            XCTAssertTrue(parseConfig("single-window-aspect-ratio = " + value).errors.isEmpty)
        }
        for value in ["-1", "-0.5", "nan", "inf", "true", "'1.5'", "[{ monitor.main = -1 }, 1.5]"] {
            XCTAssertFalse(parseConfig("single-window-aspect-ratio = " + value).errors.isEmpty)
        }
        let original = "single-window-aspect-ratio = [\n { monitor.\"Disconnected\" = 2 },\n 1.5\n]\nfocus-follows-mouse = true\n"
        let parsed = parseConfig(original)
        let rendered = renderedAspectRatio(.perMonitor(parsed.config.singleWindowAspectRatio.aspectRatioRules, default: 0))
        let updated = updateSettingsScalarConfig(in: original, section: nil, key: "single-window-aspect-ratio", renderedValue: rendered)
        let result = parseConfig(updated)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.config.singleWindowAspectRatio.defaultAspectRatio, 0)
        XCTAssertEqual(result.config.singleWindowAspectRatio.aspectRatioRules, parsed.config.singleWindowAspectRatio.aspectRatioRules)
        XCTAssertTrue(result.config.focusFollowsMouse)
    }
}
