@testable import AppBundle
import XCTest
import Common

final class ShortcutSettingsConfigEditsTest: XCTestCase {
    @MainActor
    func testSidebarDisplayModesSaveBothFlagsTogether() {
        for mode in [SettingsSidebarDisplayMode.compact, .autoHide, .expanded] {
            let text = applyingSettingsConfigEdits(mode.edits, to: "[workspace-sidebar]\nalways-expanded = true\nauto-hide = true\n")
            let parsed = parseConfig(text)
            XCTAssertTrue(parsed.errors.isEmpty)
            XCTAssertEqual(parsed.config.workspaceSidebar.alwaysExpanded, mode == .expanded)
            XCTAssertEqual(parsed.config.workspaceSidebar.autoHide, mode == .autoHide)
            XCTAssertEqual(SettingsSidebarDisplayMode(parsed.config.workspaceSidebar), mode)
        }
    }

    @MainActor
    func testGapEditsPreservePerMonitorOverrides() {
        let overrides: [PerMonitorValue<Int>] = [
            .init(description: .main, value: 12), .init(description: .secondary, value: 20),
            .init(description: .sequenceNumber(3), value: 24),
            .init(description: parseMonitorDescription("External \"Panel\"").getOrNil()!, value: 30),
        ]
        let rendered = settingsGapValue(.perMonitor(overrides, default: 8), replacingDefaultWith: 16)
        let parsed = parseConfig("[gaps]\ninner.horizontal = \(rendered)\n")
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.gaps.inner.horizontal, .perMonitor(overrides, default: 16))
        XCTAssertEqual(settingsGapValue(.constant(8), replacingDefaultWith: 16), "16")
    }

    func testCommaSeparatedListsIgnoreEmptyItemsAndAcceptNewlines() {
        XCTAssertEqual(tomlCommaSeparatedStringArray("1, 2,\n 3,, "), "[\"1\", \"2\", \"3\"]")
        XCTAssertEqual(tomlCommaSeparatedStringArray(""), "[]")
    }

    func testColorValidationMatchesConfigParser() {
        for value in ["#E1E3E4", "#E1E3E480", "#abcdef", "abcdef", "#XYZXYZ", "#123", ""] {
            XCTAssertEqual(settingsHexColorError(value) == nil, normalizedWindowBorderColor(value) != nil, value)
        }
    }

    func testCommandArraysPreserveCommasAndEscapeQuotes() {
        XCTAssertEqual(tomlStringArray("exec-and-forget echo a,b\nworkspace \"two\""),
            "[\"exec-and-forget echo a,b\", \"workspace \\\"two\\\"\"]")
    }

    func testUpdateModeBindingConfigAddsMissingSection() {
        let updated = updateModeBindingConfig(
            in: """
            start-at-login = true
            """,
            modeName: "main",
            tableKey: "binding",
            managedCommands: ["focus left"],
            assignments: ["alt-h": "focus left"]
        )

        XCTAssertTrue(updated.contains("[mode.main.binding]"))
        XCTAssertTrue(updated.contains("alt-h = \"focus left\""))
    }

    func testUpdateModeBindingConfigReplacesManagedBindingsAndPreservesCustomOnes() {
        let updated = updateModeBindingConfig(
            in: """
            [mode.main.binding]
            alt-h = "focus left"
            alt-l = "focus right"
            cmd-shift-x = "exec-and-forget open -a Xcode"
            """,
            modeName: "main",
            tableKey: "binding",
            managedCommands: ["focus left", "focus right"],
            assignments: ["alt-left": "focus left"]
        )

        XCTAssertTrue(updated.contains("alt-left = \"focus left\""))
        XCTAssertFalse(updated.contains("alt-h = \"focus left\""))
        XCTAssertFalse(updated.contains("alt-l = \"focus right\""))
        XCTAssertTrue(updated.contains("cmd-shift-x = \"exec-and-forget open -a Xcode\""))
    }

    func testReadModeBindingEntriesReadsSimpleScalarBindings() {
        let entries = readModeBindingEntries(
            in: """
            [mode.main.binding]
            alt-h = "focus left"
            "cmd-shift-/" = "reload-config"
            """,
            modeName: "main",
            tableKey: "binding"
        )

        XCTAssertEqual(entries["alt-h"], "focus left")
        XCTAssertEqual(entries["cmd-shift-/"], "reload-config")
    }

    func testInferWorkspaceShortcutStatePrefersPatternAndExtractsOverrides() {
        let state = inferWorkspaceShortcutState(
            from: [
                "alt-1": "workspace 1",
                "alt-2": "workspace 2",
                "cmd-3": "workspace 3",
                "alt-shift-1": "move-node-to-workspace 1",
                "alt-shift-2": "move-node-to-workspace 2",
                "cmd-shift-3": "move-node-to-workspace 3",
            ],
            workspaceNumbers: ["1", "2", "3"]
        )

        XCTAssertEqual(state.switchModifiers, [.option])
        XCTAssertEqual(state.moveModifiers, [.option, .shift])
        XCTAssertEqual(state.switchOverrides, ["3": "cmd-3"])
        XCTAssertEqual(state.moveOverrides, ["3": "cmd-shift-3"])
    }
}
