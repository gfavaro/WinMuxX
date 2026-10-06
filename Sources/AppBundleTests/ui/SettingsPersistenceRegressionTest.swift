@testable import AppBundle
import TOMLKit
import XCTest

@MainActor
final class SettingsPersistenceRegressionTest: XCTestCase {
    func testTabToggleUpdatesRootDottedKeysRepeatedly() throws {
        var text = "window-tabs.enabled = true # keep this explanation\nwindow-tabs.height = 36\n[animations]\nenabled = true\n"
        for enabled in [false, true, false] {
            text = updateSettingsScalarConfig(in: text, section: "window-tabs", key: "enabled", renderedValue: String(enabled))
            let parsed = parseConfig(text)
            XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
            XCTAssertEqual(parsed.config.windowTabs.enabled, enabled)
            XCTAssertEqual(parsed.config.windowTabs.height, 36)
            XCTAssertTrue(text.contains("# keep this explanation"))
            XCTAssertFalse(text.contains("[window-tabs]"))
        }
    }

    func testSidebarDateAndWeekdaySettingsPersistIndependently() {
        for dotted in [true, false] {
            var text = dotted
                ? "workspace-sidebar.show-date = true\nworkspace-sidebar.show-weekday = true\n"
                : "[workspace-sidebar]\nshow-date = true\nshow-weekday = true\n"
            for (date, weekday) in [(false, true), (true, false), (false, false), (true, true)] {
                text = applyingSettingsConfigEdits([
                    .init(section: "workspace-sidebar", key: "show-date", renderedValue: String(date)),
                    .init(section: "workspace-sidebar", key: "show-weekday", renderedValue: String(weekday)),
                ], to: text)
                let parsed = parseConfig(text)
                XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
                XCTAssertEqual(parsed.config.workspaceSidebar.showDate, date)
                XCTAssertEqual(parsed.config.workspaceSidebar.showWeekday, weekday)
                XCTAssertTrue(parsed.config.workspaceSidebar.showClock)
            }
        }
    }

    func testMissingKeyUsesExistingDottedTableAndCommentedHeader() {
        for original in ["window-tabs.height = 40\n", "[ window-tabs ] # dimensions\nheight = 40\n", "[\"window-tabs\"] # dimensions\nheight = 40\n"] {
            let updated = updateSettingsScalarConfig(in: original, section: "window-tabs", key: "enabled", renderedValue: "false")
            let parsed = parseConfig(updated)
            XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
            XCTAssertFalse(parsed.config.windowTabs.enabled)
            XCTAssertEqual(parsed.config.windowTabs.height, 40)
        }
    }

    func testNestedGapTableAndMultilineOverridesRemainValid() {
        let original = """
        [gaps.outer] # use the existing nested table
        left = [
            { monitor."Disconnected [Panel]" = 24 }, # keep override
            8 # keep default explanation
        ]
        right = 12
        [window-tabs]
        enabled = true
        """
        let rules = parseConfig(original).config.gaps.outer.left
        let updated = updateSettingsScalarConfig(in: original, section: "gaps", key: "outer.left",
            renderedValue: settingsGapValue(rules, replacingDefaultWith: 16))
        let parsed = parseConfig(updated)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.gaps.outer.left, .perMonitor(rulesForDisconnectedPanel(), default: 16))
        XCTAssertEqual(parsed.config.gaps.outer.right, .constant(12))
        XCTAssertTrue(updated.contains("# keep override"))
        XCTAssertTrue(updated.contains("# keep default explanation"))
    }

    private func rulesForDisconnectedPanel() -> [PerMonitorValue<Int>] {
        parseConfig("[gaps]\nouter.left = [{ monitor.\"Disconnected [Panel]\" = 24 }, 0]").config.gaps.outer.left.rulesForTest
    }

    func testMigrationRemovesWholeLegacyArrayAndPreservesComments() {
        let original = """
        config-version = 2
        persistent-workspaces = [
            "one", # named slot
            "two"
        ] # previous list
        window-tabs.enabled = true
        """
        let updated = applyingSettingsConfigEdits([
            .init(section: nil, key: "minimum-workspace-count", renderedValue: "0"),
            .init(section: nil, key: "persistent-workspaces", renderedValue: nil),
        ], to: original)
        let parsed = parseConfig(updated)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.minimumWorkspaceCount, 0)
        XCTAssertTrue(parsed.config.persistentWorkspaces.isEmpty)
        XCTAssertTrue(parsed.config.windowTabs.enabled)
        XCTAssertTrue(updated.contains("# named slot"))
        XCTAssertTrue(updated.contains("# previous list"))
    }

    func testMultilineStringCannotMasqueradeAsASection() throws {
        let original = "message = '''\n[window-tabs]\nenabled = false\n'''\nwindow-tabs.enabled = true\n"
        let updated = updateSettingsScalarConfig(in: original, section: "window-tabs", key: "enabled", renderedValue: "false")
        let table = try TOMLTable(string: updated)
        XCTAssertEqual(table["message"]?.string, "[window-tabs]\nenabled = false\n")
        XCTAssertEqual(table["window-tabs"]?.table?["enabled"]?.bool, false)
    }
}

private extension DynamicConfigValue where Value == Int {
    var rulesForTest: [PerMonitorValue<Int>] {
        if case .perMonitor(let rules, _) = self { return rules }
        return []
    }
}
