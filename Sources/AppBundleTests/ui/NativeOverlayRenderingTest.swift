@testable import AppBundle
import AppKit
import SwiftUI
import XCTest

/// Only synthetic offscreen controls are rendered; no desktop capture or real windows are queried.
@MainActor
final class NativeOverlayRenderingTest: WorkspaceTestCase {
    func testOverlayAppearanceUsesExpandedSidebarWhenSidebarIsHidden() {
        let monitor = mainMonitor
        TrayMenuModel.shared.workspaceSidebarVisibleWidth = 0
        TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId = workspaceSidebarMonitorScopeId(for: monitor)
        let snapshot = overlayAppearanceSnapshot(monitor: MonitorViewportId(monitor))
        XCTAssertEqual(snapshot.targetMonitorScopeId, workspaceSidebarMonitorScopeId(for: monitor))
        XCTAssertTrue(snapshot.configuration.alwaysExpanded)
        XCTAssertEqual(snapshot.visibleWidth, CGFloat(config.workspaceSidebar.width))
        XCTAssertEqual(snapshot.configuration.frostedTint, config.workspaceSidebar.frostedTint)
    }

    func testPaletteSearchAndListRenderInLightDarkAndIncreasedContrast() async throws {
        let model = SwitcherPaletteModel()
        model.items = (1...8).map { id in
            SwitcherPaletteItem(id: UInt32(id), title: "Window \(id) — A long document name to verify truncation",
                appName: "Test App", icon: nil, workspaceName: id < 5 ? "1" : "2", isFocused: false,
                workspaceTitle: id < 5 ? "Research" : "Development", projectName: "Project")
        }
        model.groupByWorkspace = true
        for (name, scheme, contrast) in [("light", ColorScheme.light, ColorSchemeContrast.standard),
                                         ("dark", .dark, .standard), ("contrast", .light, .increased)] {
            let host = NSHostingView(rootView: SwitcherPaletteView(model: model, dismiss: {})
                .environment(\.colorScheme, scheme)
                .environment(\.workspaceSidebarPreviewAccessibility,
                    WorkspaceSidebarPreviewAccessibility(reduceTransparency: true, increasedContrast: contrast == .increased)))
            let size = CGSize(width: 560, height: 440)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: contrast == .increased ? .accessibilityHighContrastAqua : (scheme == .dark ? .darkAqua : .aqua))
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: size)
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            let laidOut = expectation(description: "Native overlay layout")
            DispatchQueue.main.async { host.layoutSubtreeIfNeeded(); laidOut.fulfill() }
            await fulfillment(of: [laidOut], timeout: 2)
            let field = try XCTUnwrap(findSearchField(host))
            XCTAssertEqual(field.placeholderString, "Search windows…")
            let fieldRect = host.convert(field.bounds, from: field)
            XCTAssertGreaterThan(fieldRect.width, 200)
            XCTAssertTrue(host.bounds.contains(fieldRect))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let directory = projectRoot.appending(path: ".build/native-overlay-fixtures")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appending(path: "palette-\(name).png"))
        }
    }

    private func findSearchField(_ view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        return view.subviews.lazy.compactMap { self.findSearchField($0) }.first
    }
}
