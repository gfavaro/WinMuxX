@testable import AppBundle
import AppKit
import XCTest

final class SwitcherPaletteTest: XCTestCase {
    @MainActor
    func testNativeListSelectionAndSectionsPreserveFilteredWindowIdentities() {
        let model = SwitcherPaletteModel()
        model.items = [item(1, app: "A", title: "one", workspace: "6"),
            item(2, app: "B", title: "two", workspace: "1"),
            item(3, app: "A", title: "three", workspace: "6")]
        model.groupByWorkspace = true
        let sections = paletteResultSections(model.results)
        XCTAssertEqual(sections.map(\.workspace), ["6", "1"])
        XCTAssertEqual(sections.flatMap(\.items).map(\.id), [1, 3, 2])
        model.selectedResultId = 2
        XCTAssertEqual(model.selection, 2)
        model.moveSelection(-1)
        XCTAssertEqual(model.selectedResultId, 3)
        model.query = "two"
        XCTAssertEqual(model.selectedResultId, 2)
        model.selectedResultId = 1 // A stale list update cannot select an unrelated result.
        XCTAssertEqual(model.selectedResultId, 2)
        model.selectedResultId = nil
        XCTAssertEqual(model.selectedResultId, 2)
        model.query = "no matches"
        XCTAssertNil(model.selectedResultId)
        XCTAssertTrue(paletteResultSections(model.results).isEmpty)
    }

    @MainActor
    func testDismissReleasesCallbackAndHeldItemsAndIconsAfterTheHoldEvenWhenAlreadyHidden() {
        let model = SwitcherPaletteModel()
        let panel = SwitcherPalettePanel(model: model)
        defer { panel.close() }
        weak var retainedIcon: NSImage?
        weak var retainedCallbackOwner: NSObject?
        autoreleasepool {
            let icon = NSImage(size: NSSize(width: 32, height: 32))
            let owner = NSObject()
            retainedIcon = icon
            retainedCallbackOwner = owner
            model.items = [SwitcherPaletteItem(id: 1, title: "Window", appName: "App", icon: icon,
                workspaceName: "1", isFocused: false)]
            model.onSelect = { [owner] _ in _ = owner }
        }
        XCTAssertNotNil(retainedIcon)
        XCTAssertNotNil(retainedCallbackOwner)
        panel.dismiss()
        XCTAssertNil(retainedCallbackOwner)
        XCTAssertNotNil(retainedIcon, "Rows are held briefly so a reopen does not rebuild them")
        panel.releaseHeldContent()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(retainedIcon)
        panel.dismiss()
        XCTAssertTrue(model.results.isEmpty)
    }

    func testGroupingPreservesWorkspaceOrderAndRankingWithinGroups() {
        let original = [item(1, app: "A", title: "one", workspace: "6"),
            item(2, app: "B", title: "two", workspace: "1"),
            item(3, app: "A", title: "three", workspace: "6"),
            item(4, app: "B", title: "four", workspace: "1")]
        let ranked = [original[3], original[2], original[1], original[0]]
        XCTAssertEqual(groupSwitcherPaletteItems(ranked, workspaceOrder: original).map(\.id), [3, 1, 4, 2])
        XCTAssertEqual(groupSwitcherPaletteItems([original[3]], workspaceOrder: original).map(\.id), [4])
        XCTAssertTrue(groupSwitcherPaletteItems([], workspaceOrder: original).isEmpty)
    }

    @MainActor
    func testGroupedSelectionAndQuickSelectOnlyCountWindows() {
        let model = SwitcherPaletteModel()
        model.items = [item(1, app: "A", title: "one", workspace: "6"),
            item(2, app: "B", title: "two", workspace: "1"),
            item(3, app: "A", title: "three", workspace: "6")]
        var selected: [UInt32] = []
        model.onSelect = { selected.append($0) }
        model.groupByWorkspace = true
        XCTAssertEqual(model.results.map(\.id), [1, 3, 2])
        model.moveSelection(1); model.selectCurrent()
        model.select(at: 2)
        XCTAssertEqual(selected, [3, 2])
        model.query = "two"
        XCTAssertEqual(model.selection, 0)
        XCTAssertEqual(model.results.map(\.id), [2])
        model.query = ""; model.groupByWorkspace = false
        XCTAssertEqual(model.results.map(\.id), [1, 2, 3])
    }

    func testWorkspaceAndProjectDisplayNamesAreSearchable() {
        var candidate = item(1, app: "Safari", title: "Docs", workspace: "6")
        candidate.workspaceTitle = "Research"
        candidate.projectName = "WinMuxX"
        XCTAssertEqual(filterSwitcherPaletteItems([candidate], query: "research").map(\.id), [1])
        XCTAssertEqual(filterSwitcherPaletteItems([candidate], query: "winmuxx").map(\.id), [1])
    }

    @MainActor
    func testPaletteGroupingFlagIsOptionalAndRejectsUnknownFlags() {
        XCTAssertEqual((parseCommand("palette").cmdOrDie as? PaletteCommand)?.args.groupByWorkspace, false)
        XCTAssertEqual((parseCommand("palette --group-by-workspace").cmdOrDie as? PaletteCommand)?.args.groupByWorkspace, true)
        XCTAssertNotNil(parseCommand("palette --unknown").errorOrNil)
    }
    private func item(_ id: UInt32, app: String, title: String, workspace: String = "1") -> SwitcherPaletteItem {
        SwitcherPaletteItem(id: id, title: title, appName: app, icon: nil, workspaceName: workspace, isFocused: false)
    }

    func testEmptyQueryKeepsOriginalOrder() {
        let items = [item(1, app: "Safari", title: "Docs"), item(2, app: "Ghostty", title: "zsh")]
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "  ").map(\.id), [1, 2])
    }

    func testNonMatchingItemsAreDropped() {
        let items = [item(1, app: "Safari", title: "Docs"), item(2, app: "Ghostty", title: "zsh")]
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "ghos").map(\.id), [2])
    }

    func testWordStartAndConsecutiveMatchesRankAboveScattered() {
        let items = [
            item(1, app: "Calendar", title: "June"), // scattered "cal" not at word start? it is prefix
            item(2, app: "Books", title: "local archive"), // "cal" inside "local"
        ]
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "cal").first?.id, 1)
    }

    func testSubsequenceMatchesAcrossFields() {
        let items = [item(7, app: "Zed", title: "refresh.swift", workspace: "code")]
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "zed refresh").map(\.id), [7])
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "xyzzy").map(\.id), [])
    }

    func testFuzzyScoreRejectsNonSubsequence() {
        XCTAssertNil(switcherPaletteFuzzyScore("ba", in: "ab"))
        XCTAssertNotNil(switcherPaletteFuzzyScore("ab", in: "a-b"))
    }

    func testFinderFolderTitleIsSearchable() {
        let items = [item(8, app: "Finder", title: "Quarterly Planning")]
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "quarterly").map(\.id), [8])
    }

    @MainActor
    func testColdPaletteItemFetchesWindowTitleBeforeIndexing() async {
        setUpWorkspacesForTests()
        resetCachedWindowTitles()
        let workspace = Workspace.get(byName: "finder-palette-test")
        let window = TestWindow.new(id: 88, parent: workspace.rootTilingContainer)

        let item = await makeSwitcherPaletteItem(
            window: window,
            workspaceName: workspace.name,
            focusedWindowId: nil,
        )

        XCTAssertEqual(item.title, "TestWindow(88)")
        XCTAssertEqual(filterSwitcherPaletteItems([item], query: "testwindow").map(\.id), [88])
    }
}
