@testable import AppBundle
import XCTest

@MainActor
final class SidebarWorkspaceNumberTest: XCTestCase {
    func testNumericBadgesPreserveCommandTargetsEvenWhenAutomaticNamesCompact() {
        XCTAssertEqual((1...5).map { sidebarWorkspaceDisplayName(String($0), labels: [:]) }, ["Workspace 1", "Workspace 2", "Workspace 3", "Workspace 4", "Workspace 5"])
        XCTAssertEqual(sidebarWorkspaceDisplayName("4", labels: ["4": "  Development  "]), "Development")
    }

    func testDoubleDigitWorkspaceKeepsItsActualNumberAndBlankLabelsUseDefault() {
        XCTAssertEqual(sidebarWorkspaceDisplayName("10", labels: [:]), "Workspace 10")
        XCTAssertEqual(sidebarWorkspaceDisplayName("4", labels: ["4": "   "]), "Workspace 4")
    }

    func testGappedInternalIdsHaveContinuousPresentationNumbers() {
        let ids = ["1", "3", "4"]
        XCTAssertEqual(ids.enumerated().map {
            sidebarWorkspaceDisplayName($0.element, labels: [:], displayIndex: $0.offset + 1)
        }, ["Workspace 1", "Workspace 2", "Workspace 3"])
        XCTAssertEqual(sidebarWorkspaceDisplayName("4", labels: ["4": "Development"], displayIndex: 3), "Development")
    }
}
