@testable import AppBundle
import XCTest

@MainActor
final class AccessibleAlternativesTest: XCTestCase {
    func testTabMoveTargetStopsAtStripEnds() {
        let tabs = [1, 2, 3].map(makeTab)

        XCTAssertNil(windowTabStripMoveTargetIndex(1, by: -1, in: tabs))
        XCTAssertEqual(windowTabStripMoveTargetIndex(1, by: 1, in: tabs), 1)
        XCTAssertEqual(windowTabStripMoveTargetIndex(2, by: -1, in: tabs), 0)
        XCTAssertEqual(windowTabStripMoveTargetIndex(2, by: 1, in: tabs), 2)
        XCTAssertNil(windowTabStripMoveTargetIndex(3, by: 1, in: tabs))
    }

    func testTabMoveTargetIgnoresUnknownAndSingleTabs() {
        XCTAssertNil(windowTabStripMoveTargetIndex(9, by: 1, in: [1, 2].map(makeTab)))
        XCTAssertNil(windowTabStripMoveTargetIndex(1, by: -1, in: [makeTab(1)]))
        XCTAssertNil(windowTabStripMoveTargetIndex(1, by: 1, in: [makeTab(1)]))
    }

    func testTabGroupLabelSpeaksCountOnlyForStacks() {
        XCTAssertEqual(workspaceSidebarTabGroupAccessibilityLabel(title: "Docs", windowCount: 3), "Docs, 3 tabs")
        XCTAssertEqual(workspaceSidebarTabGroupAccessibilityLabel(title: "Docs", windowCount: 1), "Docs")
        XCTAssertEqual(workspaceSidebarTabGroupAccessibilityLabel(title: "", windowCount: 2), "Tab Group, 2 tabs")
    }

    func testNoSearchMatchesNeedsAFilteringQueryAndAnEmptyPage() {
        let workspace = WorkspaceSidebarWorkspaceViewModel(
            name: "coding", projectId: "default", displayName: "Coding", sidebarLabel: "",
            isGeneratedName: false, monitorScopeId: "main", monitorName: nil,
            isFocused: true, isVisible: true, items: [],
        )

        XCTAssertTrue(workspaceSidebarShowsNoSearchMatches(query: "zzz", pageWorkspaces: []))
        XCTAssertFalse(workspaceSidebarShowsNoSearchMatches(query: "zzz", pageWorkspaces: [workspace]))
        XCTAssertFalse(workspaceSidebarShowsNoSearchMatches(query: "", pageWorkspaces: []))
        // Whitespace does not filter, so an empty project is not a failed search.
        XCTAssertFalse(workspaceSidebarShowsNoSearchMatches(query: "   ", pageWorkspaces: []))
    }
}

private func makeTab(_ windowId: UInt32) -> WindowTabItemViewModel {
    WindowTabItemViewModel(
        windowId: windowId, workspaceName: "tabs", appName: "App", appBundleId: nil,
        appBundlePath: nil, title: "Window \(windowId)", isActive: windowId == 1,
    )
}
