@testable import AppBundle
import AppKit
import Common
import XCTest

extension ConfigTest {
    func testUpdateWorkspaceSidebarLabelConfigAddsSectionWhenMissing() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [mode.main.binding]
                alt-h = 'focus left'
            """,
            workspaceName: "1",
            label: "Code",
        )

        XCTAssertTrue(updated.contains("[workspace-sidebar.workspace-labels]"))
        XCTAssertTrue(updated.contains("\"1\" = \"Code\""))
    }

    func testUpdateWorkspaceSidebarLabelConfigReplacesExistingLabel() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [workspace-sidebar.workspace-labels]
            "1" = "Old"
            "2" = "Web"
            """,
            workspaceName: "1",
            label: "Code",
        )

        XCTAssertTrue(updated.contains("\"1\" = \"Code\""))
        XCTAssertFalse(updated.contains("\"1\" = \"Old\""))
        XCTAssertTrue(updated.contains("\"2\" = \"Web\""))
    }

    func testUpdateWorkspaceSidebarLabelConfigAddsNewLabelWithoutExtraBlankLine() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [workspace-sidebar.workspace-labels]
            "1" = "Code"
            """,
            workspaceName: "2",
            label: "Web",
        )

        XCTAssertEqual(
            updated,
            """
            [workspace-sidebar.workspace-labels]
            "1" = "Code"
            "2" = "Web"
            """,
        )
    }

    func testUpdateWorkspaceSidebarLabelConfigRemovesLastLabelSection() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [workspace-sidebar.workspace-labels]
            "1" = "Code"

            [mode.main.binding]
                alt-h = 'focus left'
            """,
            workspaceName: "1",
            label: nil,
        )

        XCTAssertFalse(updated.contains("[workspace-sidebar.workspace-labels]"))
        XCTAssertTrue(updated.contains("[mode.main.binding]"))
    }

    func testUpdateWorkspaceSidebarProjectColorConfigAddsAndReplacesColor() {
        let added = updateWorkspaceSidebarProjectColorConfig(
            in: """
            [workspace-sidebar]
                enabled = true
            """,
            projectId: "project-1",
            colorHex: "#60A5FA",
        )

        XCTAssertTrue(added.contains("[workspace-sidebar.project-colors]"))
        XCTAssertTrue(added.contains("\"project-1\" = \"#60A5FA\""))

        let replaced = updateWorkspaceSidebarProjectColorConfig(
            in: added,
            projectId: "project-1",
            colorHex: "#F87171",
        )

        XCTAssertTrue(replaced.contains("\"project-1\" = \"#F87171\""))
        XCTAssertFalse(replaced.contains("\"project-1\" = \"#60A5FA\""))
    }

    func testUpdateWorkspaceSidebarProjectColorConfigRemovesLastColorSection() {
        let updated = updateWorkspaceSidebarProjectColorConfig(
            in: """
            [workspace-sidebar.project-colors]
            "project-1" = "#60A5FA"

            [mode.main.binding]
                alt-h = 'focus left'
            """,
            projectId: "project-1",
            colorHex: nil,
        )

        XCTAssertFalse(updated.contains("[workspace-sidebar.project-colors]"))
        XCTAssertTrue(updated.contains("[mode.main.binding]"))
    }

}
