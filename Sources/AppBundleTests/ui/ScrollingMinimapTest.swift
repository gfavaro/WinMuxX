@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class ScrollingMinimapTest: WorkspaceTestCase {
    private func fixture(count: Int = 3) -> (Workspace, [TestWindow]) {
        let workspace = focus.workspace
        let windows = (0..<count).map { TestWindow.new(id: UInt32(95500 + $0), parent: workspace.rootTilingContainer) }
        workspace.arrangement = .scrolling
        return (workspace, windows)
    }

    func testMapPreservesWidthRatiosAndTracksClampedViewport() throws {
        let (workspace, windows) = fixture()
        windows[0].scrollingColumnWidth = 0.25
        windows[1].scrollingColumnWidth = 0.5
        windows[2].scrollingColumnWidth = 0.75
        let metrics = workspace.scrollingMetrics
        let bounds = CGRect(x: 16, y: 32, width: 608, height: 58)
        let first = ScrollingMinimapGeometry(metrics: metrics, offset: metrics.offsetRange.lowerBound, bounds: bounds)
        let last = ScrollingMinimapGeometry(metrics: metrics, offset: metrics.offsetRange.upperBound, bounds: bounds)
        XCTAssertEqual(first.tiles[1].width / first.tiles[0].width, metrics.columns[1].width / metrics.columns[0].width, accuracy: 0.001)
        XCTAssertEqual(first.tiles[2].width / first.tiles[0].width, metrics.columns[2].width / metrics.columns[0].width, accuracy: 0.001)
        XCTAssertEqual(first.viewport.width / first.viewport.height,
                       metrics.areaWidth / metrics.geometry.area.height, accuracy: 0.001)
        for (tile, column) in zip(first.tiles, metrics.columns) {
            XCTAssertEqual(tile.width / tile.height, column.width / metrics.geometry.area.height, accuracy: 0.001)
        }
        XCTAssertLessThanOrEqual(first.tiles[0].minX, first.viewport.midX)
        XCTAssertEqual(last.tiles[2].maxX, last.viewport.maxX, accuracy: 1)
        XCTAssertGreaterThan(last.viewport.minX, first.viewport.minX)
        XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(first.viewport))
        XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(last.viewport))
    }

    func testSingleWindowKeepsItsRealAspectRatioInsteadOfStretchingAcrossThePanel() throws {
        let (workspace, _) = fixture(count: 1)
        let metrics = workspace.scrollingMetrics
        let map = ScrollingMinimapGeometry(metrics: metrics, offset: 0,
            bounds: CGRect(x: 0, y: 0, width: 648, height: 58))
        let tile = try XCTUnwrap(map.tiles.first)
        XCTAssertEqual(tile.width / tile.height, metrics.columns[0].width / metrics.geometry.area.height, accuracy: 0.001)
        XCTAssertLessThan(tile.width, 648, "A lone window must not be stretched to the entire panel width")
        XCTAssertEqual(tile.midX, 324, accuracy: 0.01)
        XCTAssertEqual(map.viewport, tile)
    }

    func testDenseTilesAndGapsRemainSelectable() throws {
        let (workspace, _) = fixture(count: 40)
        let map = ScrollingMinimapGeometry(metrics: workspace.scrollingMetrics, offset: 0,
            bounds: CGRect(x: 0, y: 0, width: 608, height: 58))
        for (index, frame) in map.tiles.enumerated() {
            XCTAssertEqual(map.column(at: CGPoint(x: frame.midX, y: frame.midY)), index)
        }
        for x in stride(from: CGFloat(0), to: 608, by: 2) {
            XCTAssertNotNil(map.column(at: CGPoint(x: x, y: 29)))
        }
        XCTAssertNil(map.column(at: CGPoint(x: -1, y: 29)))
    }

    func testUnequalDenseMinimapTilesStayAtLeastThirtyTwoPointsAndDoNotOverlap() {
        let (workspace, windows) = fixture(count: 40)
        for (index, window) in windows.enumerated() {
            window.scrollingColumnWidth = index == 0 ? 0.1 : index == 1 ? 0.2 : 1
        }
        let metrics = workspace.scrollingMetrics
        let contentWidth = scrollingMinimapContentWidth(metrics: metrics, visibleWidth: 608)
        let map = ScrollingMinimapGeometry(metrics: metrics, offset: 0,
            bounds: CGRect(x: 0, y: 0, width: contentWidth, height: scrollingMinimapRowHeight(metrics: metrics)))
        XCTAssertGreaterThan(contentWidth, 608)
        for tile in map.tiles { XCTAssertGreaterThanOrEqual(tile.width, 32) }
        for pair in zip(map.tiles, map.tiles.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.maxX, pair.1.minX + 0.01)
        }
    }

    func testScrollCanvasKeepsTilesAlignedAndFollowsTheVisibleEndOfTheWorkspace() throws {
        let (workspace, windows) = fixture(count: 40)
        let metrics = workspace.scrollingMetrics
        let models = windows.map { ScrollingMinimapTile(id: ObjectIdentifier($0), title: "Window", applications: [], count: 1, tabs: false, horizontalSplit: false) }
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 640, height: 120))
        view.update(workspaceName: workspace.name, models: models, icons: [:], metrics: metrics,
                    offset: metrics.offsetRange.upperBound, focused: ObjectIdentifier(windows[39]))
        let scroll = try XCTUnwrap(minimapDescendants(of: view).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertTrue(document.isFlipped, "The scroll canvas must use the map's top-left coordinates")
        let buttons = document.subviews.compactMap { $0 as? NSButton }
        let first = try XCTUnwrap(buttons.first)
        let last = try XCTUnwrap(buttons.last)
        XCTAssertEqual(view.convert(first.bounds, from: first).minY, 29, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(first.bounds.height, 50, "The label extends to y=50 and must fit inside the tile")
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, 0)
        XCTAssertTrue(scroll.documentVisibleRect.intersects(last.frame), "The map must follow the viewport at the strip end")
        view.resetPresentation()
        view.update(workspaceName: workspace.name, models: models, icons: [:], metrics: metrics,
                    offset: metrics.offsetRange.lowerBound, focused: ObjectIdentifier(windows[0]))
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.01)
    }

    func testPausedPanAndHoverDoNotExpireAndExitGetsFullGracePeriod() throws {
        var lifetime = ScrollingMinimapLifetime()
        lifetime.activity(at: 0)
        XCTAssertEqual(lifetime.dismissalDelay(at: 0.5), 1)
        lifetime.pan(true, at: 0.6)
        XCTAssertNil(lifetime.dismissalDelay(at: 100))
        lifetime.pan(false, at: 100)
        XCTAssertEqual(lifetime.dismissalDelay(at: 100), 1.5)
        lifetime.hover(true, at: 101.4)
        XCTAssertNil(lifetime.dismissalDelay(at: 200))
        lifetime.hover(false, at: 200)
        XCTAssertEqual(lifetime.dismissalDelay(at: 201), 0.5)
        lifetime.activity(at: 201)
        XCTAssertEqual(lifetime.dismissalDelay(at: 201.5), 1)
        XCTAssertEqual(lifetime.dismissalDelay(at: 203), 0)
    }

    func testClickUsesGroupIdentityAfterReorderAndRevealsWithoutRebuilding() async throws {
        let (workspace, windows) = fixture()
        let root = workspace.rootTilingContainer
        let selected = windows[2]
        let id = ObjectIdentifier(selected)
        selected.unbindFromParent()
        selected.bind(to: root, adaptiveWeight: 1, index: 0)
        let groups = root.children
        let metrics = workspace.scrollingMetrics
        let column = try XCTUnwrap(metrics.columns.first(where: { $0.node === selected }))
        let expected = metrics.revealedOffset(for: column, current: workspace.scrollingOffset)
        XCTAssertTrue(focusScrollingMinimapGroup(id, in: workspace))
        try await workspace.layoutWorkspace()
        XCTAssertTrue(focus.windowOrNil === selected)
        XCTAssertEqual(workspace.scrollingOffset, expected, accuracy: 1)
        XCTAssertEqual(root.children, groups)
        selected.unbindFromParent()
        XCTAssertFalse(focusScrollingMinimapGroup(id, in: workspace))
    }

    func testCommandValidationAndDefaultShortcut() async throws {
        let (workspace, _) = fixture()
        let command = try XCTUnwrap(parseCommand("scrolling-minimap").cmdOrNil)
        XCTAssertTrue(command.isPresentation)
        let shown = try await command.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(shown.exitCode, 0)
        workspace.arrangement = .dwindle
        let wrongMode = try await command.run(.defaultEnv, .emptyStdin)
        XCTAssertNotEqual(wrongMode.exitCode, 0)
        workspace.arrangement = .scrolling
        config.scrolling.minimapEnabled = false
        let disabled = try await command.run(.defaultEnv, .emptyStdin)
        XCTAssertNotEqual(disabled.exitCode, 0)
        XCTAssertTrue(defaultConfig.modes[mainModeId]?.bindings["alt-ctrl-m"]?.commands.first is ScrollingMinimapCommand)
    }

    func testExplicitOpenHoldsAndKeyboardSelectionSurvivesModelRefresh() throws {
        var lifetime = ScrollingMinimapLifetime()
        lifetime.openExplicitly(at: 1)
        XCTAssertTrue(lifetime.isExplicitlyOpen)
        XCTAssertNil(lifetime.dismissalDelay(at: 500))
        lifetime.closeExplicitly()
        XCTAssertEqual(lifetime.dismissalDelay(at: 500), 0)
        let (workspace, windows) = fixture()
        let models = windows.map { ScrollingMinimapTile(id: ObjectIdentifier($0), title: "Window", applications: [], count: 1, tabs: false, horizontalSplit: false) }
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 600, height: 120))
        var selected: ObjectIdentifier?
        var dismissed = false
        view.selected = { selected = $0 }
        view.dismissRequested = { dismissed = true }
        func update() {
            view.update(workspaceName: workspace.name, models: models, icons: [:], metrics: workspace.scrollingMetrics,
                        offset: workspace.scrollingOffset, focused: ObjectIdentifier(windows[0]))
        }
        func key(_ code: UInt16) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        }
        update()
        view.beginKeyboardNavigation()
        view.keyDown(with: try key(124))
        update()
        view.keyDown(with: try key(36))
        XCTAssertEqual(selected, ObjectIdentifier(windows[1]))
        view.keyDown(with: try key(53))
        XCTAssertTrue(dismissed)
    }

    func testRenderAccessibleTilesInLightAndDarkLayouts() throws {
        let (workspace, windows) = fixture()
        windows[0].scrollingColumnWidth = 0.25
        windows[1].scrollingColumnWidth = 0.5
        windows[2].scrollingColumnWidth = 0.75
        let titles = ["Design system", "WinMuxX · scrolling workspaces", "Research and references"]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WinMuxX-minimap-previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let host = MinimapPreviewHost(frame: CGRect(x: 0, y: 0, width: 640,
                height: scrollingMinimapRowHeight(metrics: workspace.scrollingMetrics) + 62))
            let view = ScrollingMinimapView(frame: host.bounds)
            host.addSubview(view)
            let window = NSWindow(contentRect: host.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
            window.orderFront(nil)
            defer { window.close() }
            let models = windows.enumerated().map { index, window in
                ScrollingMinimapTile(id: ObjectIdentifier(window), title: titles[index], applications: [Int32(index)],
                    count: index + 1, tabs: index == 1, horizontalSplit: true)
            }
            let icons = [0: "paintpalette.fill", 1: "terminal.fill", 2: "doc.text.fill"].compactMapValues {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)
            }
            view.update(workspaceName: "Code", models: models, icons: Dictionary(uniqueKeysWithValues: icons.map { (Int32($0.key), $0.value) }),
                        metrics: workspace.scrollingMetrics, offset: 350, focused: ObjectIdentifier(windows[1]))
            let buttons = minimapDescendants(of: view).compactMap { $0 as? NSButton }
            XCTAssertEqual(buttons.count, 3)
            for (index, button) in buttons.enumerated() {
                XCTAssertGreaterThanOrEqual(button.frame.width, 32)
                XCTAssertTrue(button.superview?.bounds.contains(button.frame) == true)
                XCTAssertTrue(button.accessibilityLabel()?.contains(titles[index]) == true)
            }
            view.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            let selectedTile = view.convert(buttons[1].bounds, from: buttons[1])
            let tileColor = bitmap.colorAt(x: Int(selectedTile.midX * scale), y: Int((selectedTile.minY + 5) * scale))
            let background = bitmap.colorAt(x: Int(5 * scale), y: Int(100 * scale))
            XCTAssertNotEqual(tileColor, background, "The preview must contain rendered tiles, not a blank host")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("\(appearance.rawValue).png"))
        }
    }
}

@MainActor
private func minimapDescendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + minimapDescendants(of: $0) }
}

@MainActor
private final class MinimapPreviewHost: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}
