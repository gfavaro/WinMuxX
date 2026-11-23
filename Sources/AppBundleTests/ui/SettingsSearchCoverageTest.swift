@testable import AppBundle
import Foundation
import XCTest

/// Every control a Settings page draws must be a search result, so a new control cannot ship
/// unfindable. Controls that are not single settings are listed in `notSearchable`.
final class SettingsSearchCoverageTest: XCTestCase {
    /// Draft keys that are views of other controls or derived values, not controls of their own.
    private let notSearchable: Set<String> = [
        "persistent-workspaces", // Workspaces page editor
        "shortcuts-preset", // Shortcuts page
        "workspace-sidebar.solid-chrome-color", // color palette under Shared appearance
        "workspace-sidebar.solid-chrome-custom-color",
        "workspace-sidebar.frosted-tint",
        "borders.active-color", "borders.exclude-apps", "borders.width", // hidden until borders are on or shown in a collapsed group
        "enable-normalization-flatten-containers", "enable-normalization-opposite-orientation-for-nested-containers", // advanced group
        "after-startup-command", "exec-on-workspace-change", "on-display-changed", "on-focus-changed", // Automation page sections
        "on-focused-monitor-changed", "on-mode-changed",
        "modifiers.alt", "modifiers.cmd", "modifiers.ctrl", "modifiers.shift", // Shortcuts page
    ]

    func testEveryDraftSettingIsSearchable() throws {
        let settings = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("AppBundle/ui/settings")
        let files = try FileManager.default.contentsOfDirectory(at: settings, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let pattern = try NSRegularExpression(pattern: #"@SettingsDraft\("([a-z0-9.-]+)""#)
        var keys: Set<String> = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                keys.insert(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        XCTAssertGreaterThan(keys.count, 40, "The scan found too few settings; the source path may have moved")
        let searchable = Set(SettingsControl.allCases.map(\.id))
        let missing = keys.subtracting(searchable).subtracting(notSearchable).sorted()
        XCTAssertEqual(missing, [], "Add these to SettingsControl so Settings search finds them")
    }
}
