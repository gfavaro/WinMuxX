@testable import AppBundle
import AppKit
import SwiftUI
import XCTest

/// Renders our own test component, not the desktop or the installed application.
@MainActor
final class SettingsRefinementRenderingTest: WorkspaceTestCase {

    func testRuleEditorActionsFitCompactAndWideLayouts() throws {
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        defer { NSApplication.shared.accessibilitySetValue(false, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")) }
        for size in [CGSize(width: 500, height: 360), CGSize(width: 500, height: 650), CGSize(width: 900, height: 650)] {
            let width = size.width
            let rules = SettingsWindowRulesModel(readText: {
                "[[on-window-detected]]\nif.app-id = 'com.example.long-application-name'\nrun = ['exec-and-forget echo custom', 'layout floating']\n"
            })
            rules.load(); rules.select(0)
            rules.draft?.titleRegex = "Preferences"
            let view = SettingsWindowRulesView(model: ShortcutSettingsModel(drafts: SettingsDraftStore()), rules: rules, onRawEditor: {})
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: size)
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            window.orderFront(nil)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let frame = window.convertToScreen(host.convert(host.bounds, to: nil))
            let buttons = accessibilityButtons(host)
            for title in ["Add rule", "Save", "Revert", "Configuration editor…"] {
                let button = try XCTUnwrap(buttons.first { ($0.accessibilityLabel?() ?? $0.accessibilityTitle?()) == title }, "Missing \(title) at width \(width)")
                let bounds = try XCTUnwrap(button.accessibilityFrame?())
                XCTAssertGreaterThan(bounds.width, 0)
                XCTAssertTrue(frame.insetBy(dx: -1, dy: -1).contains(bounds), "\(title) overflows the editor at width \(width): \(bounds) outside \(frame)")
            }
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WinMuxX-settings-previews")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("rules-\(Int(width))x\(Int(size.height)).png"))
        }
    }

    private func accessibilityButtons(_ element: AnyObject) -> [AnyObject] {
        var result: [AnyObject] = element.accessibilityRole?() == .button ? [element] : []
        for child in element.accessibilityChildren?() ?? [] {
            result += accessibilityButtons(child as AnyObject)
        }
        return result
    }
}
