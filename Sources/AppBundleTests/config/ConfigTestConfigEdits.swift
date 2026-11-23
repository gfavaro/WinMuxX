@testable import AppBundle
import AppKit
import Common
import XCTest

/// The sidebar writes labels and colors through the same TOML editor as Settings; these check that
/// what it writes parses back to the same entries and leaves everything else alone.
extension ConfigTest {
    private func edited(_ text: String, _ edit: SettingsConfigEdit) -> (text: String, sidebar: WorkspaceSidebarConfig) {
        let updated = applyingSettingsConfigEdits([edit], to: text)
        let result = parseConfig("config-version = 2\n" + updated)
        XCTAssertTrue(result.errors.isEmpty, "\(result.errors)\n\(updated)")
        return (updated, result.config.workspaceSidebar)
    }

    func testSidebarLabelIsAddedWhenNoTableExists() {
        let (text, sidebar) = edited("[mode.main.binding]\n    alt-h = 'focus left'", workspaceSidebarLabelEdit(workspaceName: "1", label: "Code"))
        XCTAssertEqual(sidebar.workspaceLabels["1"], "Code")
        XCTAssertTrue(text.contains("alt-h = 'focus left'"))
    }

    func testSidebarLabelReplacesTheExistingOneAndKeepsTheOthers() {
        let (_, sidebar) = edited(
            "[workspace-sidebar.workspace-labels]\n\"1\" = \"Old\"\n\"2\" = \"Web\"",
            workspaceSidebarLabelEdit(workspaceName: "1", label: "Code"),
        )
        XCTAssertEqual(sidebar.workspaceLabels, ["1": "Code", "2": "Web"])
    }

    func testSidebarLabelIsAppendedToTheExistingTable() {
        let (text, sidebar) = edited(
            "[workspace-sidebar.workspace-labels]\n\"1\" = \"Code\"",
            workspaceSidebarLabelEdit(workspaceName: "2", label: "Web"),
        )
        XCTAssertEqual(sidebar.workspaceLabels, ["1": "Code", "2": "Web"])
        XCTAssertFalse(text.contains("\n\n"), "No blank line is added inside the table")
    }

    func testRemovingTheLastSidebarLabelLeavesOtherSettingsAlone() {
        let (text, sidebar) = edited(
            "[workspace-sidebar.workspace-labels]\n\"1\" = \"Code\"\n\n[mode.main.binding]\n    alt-h = 'focus left'",
            workspaceSidebarLabelEdit(workspaceName: "1", label: nil),
        )
        XCTAssertTrue(sidebar.workspaceLabels.isEmpty)
        XCTAssertTrue(text.contains("[mode.main.binding]"))
        XCTAssertTrue(text.contains("alt-h = 'focus left'"))
    }

    func testSidebarKeysWithDotsStayOneKey() {
        let (_, sidebar) = edited("", workspaceSidebarProjectLabelEdit(projectId: "my.project", label: "Mine"))
        XCTAssertEqual(sidebar.projectLabels["my.project"], "Mine")
    }

    func testSidebarProjectColorIsAddedReplacedAndRemoved() {
        let (added, afterAdd) = edited("[workspace-sidebar]\n    enabled = true", workspaceSidebarProjectColorEdit(projectId: "project-1", colorHex: "#60A5FA"))
        XCTAssertEqual(afterAdd.projectColors["project-1"], "#60A5FA")
        XCTAssertTrue(afterAdd.enabled)

        let (replaced, afterReplace) = edited(added, workspaceSidebarProjectColorEdit(projectId: "project-1", colorHex: "#F87171"))
        XCTAssertEqual(afterReplace.projectColors["project-1"], "#F87171")

        let (_, afterRemove) = edited(replaced, workspaceSidebarProjectColorEdit(projectId: "project-1", colorHex: nil))
        XCTAssertTrue(afterRemove.projectColors.isEmpty)
    }
}
