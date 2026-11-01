@testable import AppBundle
import XCTest

final class WorkspaceSidebarOtherDisplayTest: XCTestCase {
    private func workspace(scope: String, visible: Bool) -> WorkspaceSidebarWorkspaceViewModel {
        WorkspaceSidebarWorkspaceViewModel(name: "1", projectId: "default", displayName: "1", sidebarLabel: "",
            isGeneratedName: false, monitorScopeId: scope, monitorName: "S34CG50",
            isFocused: false, isVisible: visible, items: [])
    }

    func testOnlyAWorkspaceShowingOnAnotherDisplayIsMarked() {
        XCTAssertTrue(workspaceSidebarWorkspaceIsShownOnOtherDisplay(workspace(scope: "external", visible: true), selectedScopeId: "builtin"))
        // Another display owns many hidden workspaces; marking them all would mark nothing useful.
        XCTAssertFalse(workspaceSidebarWorkspaceIsShownOnOtherDisplay(workspace(scope: "external", visible: false), selectedScopeId: "builtin"))
        XCTAssertFalse(workspaceSidebarWorkspaceIsShownOnOtherDisplay(workspace(scope: "builtin", visible: true), selectedScopeId: "builtin"))
    }

    func testAggregateScopesMarkNothing() {
        for scope in [workspaceSidebarDefaultScopeId, workspaceSidebarFocusedScopeId] {
            XCTAssertFalse(workspaceSidebarWorkspaceIsShownOnOtherDisplay(workspace(scope: "external", visible: true), selectedScopeId: scope))
        }
    }
}
