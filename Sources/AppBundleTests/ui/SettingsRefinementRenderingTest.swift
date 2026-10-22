@testable import AppBundle
import AppKit
import Common
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
            var document = "[[on-window-detected]]\nif.app-id = 'com.example.long-application-name'\nrun = ['exec-and-forget echo custom', 'layout floating']\n"
            let rules = SettingsWindowRulesModel(readText: { document })
            rules.load(); rules.select(0)
            rules.draft?.titleRegex = "Preferences"
            let access = SettingsConfigAccess(edit: { transform in
                document = try transform(document)
                return URL(filePath: "/unused-render-fixture")
            }, reload: { _ in true })
            let view = SettingsWindowRulesView(model: ShortcutSettingsModel(configAccess: access, drafts: SettingsDraftStore()), rules: rules, onRawEditor: {})
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
            for title in ["Add rule", "Discard changes", "Configuration editor…"] {
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

    func testModeOptionsRenderFromConfigWithoutSavingOnLoad() throws {
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        defer { NSApplication.shared.accessibilitySetValue(false, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")) }
        config = parseConfig("""
        [mode.main.binding]
        [mode.navigation]
        timeout-ms = 1500
        show-indicator = true
        indicator-color = '#5E9EFF'
        [mode.navigation.binding]
        esc = 'mode main'
        """).config
        var writes = 0
        let model = ShortcutSettingsModel(configAccess: .init(edit: { _ in
            writes += 1
            return URL(filePath: "/unused-render-fixture")
        }, reload: { _ in true }), drafts: SettingsDraftStore())
        for scheme in [ColorScheme.light, .dark] {
            let root = Form { SettingsModeOptionsView(model: model, initialMode: "navigation") }
                .formStyle(.grouped).environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 550, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let labels = accessibilityLabels(host)
            XCTAssertTrue(labels.contains { $0.contains("Inactivity timeout") }, labels.joined(separator: ", "))
            XCTAssertTrue(labels.contains { $0.contains("Show mode indicator") }, labels.joined(separator: ", "))
            XCTAssertTrue(labels.contains { $0.contains("Use system accent color") }, labels.joined(separator: ", "))
            window.close()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(writes, 0, "Loading Settings must not save existing config values")
    }

    private func accessibilityLabels(_ element: AnyObject) -> [String] {
        var labels = [element.accessibilityLabel?(), element.accessibilityTitle?()].compactMap { $0 }
        for child in element.accessibilityChildren?() ?? [] { labels += accessibilityLabels(child as AnyObject) }
        return labels
    }

    private func accessibilityButtons(_ element: AnyObject) -> [AnyObject] {
        var result: [AnyObject] = element.accessibilityRole?() == .button ? [element] : []
        for child in element.accessibilityChildren?() ?? [] {
            result += accessibilityButtons(child as AnyObject)
        }
        return result
    }
}
