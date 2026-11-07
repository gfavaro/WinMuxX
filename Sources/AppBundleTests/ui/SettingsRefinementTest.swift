@testable import AppBundle
import Common
import XCTest

@MainActor
final class SettingsRefinementTest: WorkspaceTestCase {

    func testSearchRequestsRemainDistinctAndReadinessIgnoresUnrelatedFields() {
        let first = SettingsSearchDestination(id: "borders.enabled")
        let repeated = SettingsSearchDestination(id: "borders.enabled")
        XCTAssertNotEqual(first, repeated)
        var ready: SettingsSearchDestination?
        SettingsSearchReadyKey.reduce(value: &ready, nextValue: { first })
        SettingsSearchReadyKey.reduce(value: &ready, nextValue: { nil })
        XCTAssertEqual(ready, first)
        SettingsSearchReadyKey.reduce(value: &ready, nextValue: { repeated })
        XCTAssertEqual(ready, repeated)
    }

    func testDisplayMoveTargetSurvivesRepositioningAndRejectsMissingDisplays() {
        var original = TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "External",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080), isMain: true)
        original.displayUUID = "physical-display"
        setMonitorsForTests([original])
        defer { setMonitorsForTests(nil) }
        XCTAssertEqual(workspaceSidebarMonitor(forDisplayUUID: "PHYSICAL-DISPLAY")?.name, "External")
        var replacement = TestMonitor(monitorAppKitNsScreenScreensId: 2, name: "Replacement",
            rect: original.rect, visibleRect: original.visibleRect, isMain: true)
        replacement.displayUUID = "different-display"
        var moved = TestMonitor(monitorAppKitNsScreenScreensId: 1, name: "External",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080), isMain: false)
        moved.displayUUID = original.displayUUID
        setMonitorsForTests([replacement, moved])
        XCTAssertEqual(workspaceSidebarMonitor(forDisplayUUID: original.displayUUID)?.rect.topLeftCorner, moved.rect.topLeftCorner)
        setMonitorsForTests([replacement])
        XCTAssertNil(workspaceSidebarMonitor(forDisplayUUID: original.displayUUID))
        XCTAssertNil(workspaceSidebarMonitor(forDisplayUUID: nil))
        XCTAssertNil(workspaceSidebarMonitor(forDisplayUUID: ""))
    }

    func testUnmappedReferenceSettingsAreDiscoverableInConfiguration() {
        for query in ["on-window-detected", "inherit-env-vars"] {
            XCTAssertTrue(SettingsSidebarItem.configuration.matchesSearch(query), query)
        }
        let unmapped = configurationReferenceSections.filter { $0.pane == nil }
        XCTAssertFalse(unmapped.isEmpty)
        for section in unmapped {
            XCTAssertTrue(SettingsSidebarItem.configuration.matchesSearch(section.title), section.id)
        }
        XCTAssertFalse(SettingsSidebarItem.configuration.matchesSearch("nonexistent-setting"))
        XCTAssertFalse(SettingsSidebarItem.general.matchesSearch("inherit-env-vars"))
        XCTAssertTrue(SettingsSidebarItem.windows.matchesSearch("fullscreen-width"))
    }

    func testPageSearchKeepsOrderFallbacksAndMultiwordMatching() {
        let pages: [SettingsSidebarItem] = [.configuration, .windows, .general, .shortcuts]
        XCTAssertEqual(settingsPageSearchResults("  ", pages: pages), pages)
        XCTAssertEqual(settingsPageSearchResults("inherit-env-vars", pages: pages), [.configuration])
        XCTAssertEqual(settingsPageSearchResults("keyboard hotkeys", pages: pages), [.shortcuts])
        XCTAssertTrue(settingsPageSearchResults("keyboard nonexistent", pages: pages).isEmpty)
        XCTAssertEqual(Set(SettingsControl.allCases.map(\.id)).count, SettingsControl.allCases.count)
    }

    func testExplicitSettingsOpenRequestsRemainDistinct() {
        let model = ShortcutSettingsModel(configAccess: .init(edit: { _ in
            XCTFail("Opening Settings must not write configuration")
            return URL(filePath: "/unused-open-fixture")
        }, reload: { _ in true }), drafts: SettingsDraftStore())
        XCTAssertEqual(model.openRequestId, 0)
        model.requestWindowOpen()
        XCTAssertEqual(model.openRequestId, 1)
        model.requestWindowOpen()
        XCTAssertEqual(model.openRequestId, 2)
    }

    func testReturnOpensTheFirstControlResultThenTheFirstPage() {
        let controls = settingsControlSearchResults("login")
        let pages = settingsPageSearchResults("login", pages: SettingsSidebarItem.allCases)
        XCTAssertEqual(settingsSearchSubmitSelection(controls: controls, pages: pages), controls.first.map { .control($0) })
        XCTAssertEqual(settingsSearchSubmitSelection(controls: [], pages: [.displays, .general]), .page(.displays))
        XCTAssertNil(settingsSearchSubmitSelection(controls: [], pages: []))
    }

    func testCommandFFocusesSearchButOtherShortcutsDoNot() {
        XCTAssertTrue(isSettingsFindShortcut(.command, "f"))
        XCTAssertTrue(isSettingsFindShortcut([.command, .capsLock], "F"))
        XCTAssertFalse(isSettingsFindShortcut([.command, .shift], "f"))
        XCTAssertFalse(isSettingsFindShortcut([.command, .option], "f"))
        XCTAssertFalse(isSettingsFindShortcut(.command, "g"))
        XCTAssertFalse(isSettingsFindShortcut([], "f"))
    }

    func testControlSearchFindsSpecificDestinations() {
        let borders = settingsControlSearchResults("borders")
        XCTAssertTrue(borders.contains { $0.id == "borders.enabled" && $0.page == .appearance })
        XCTAssertEqual(settingsControlSearchResults("fullscreen-width").map(\.id), ["fullscreen-width"])
        XCTAssertTrue(settingsControlSearchResults("START LOGIN").contains { $0.id == "start-at-login" })
        XCTAssertTrue(settingsControlSearchResults("  ").isEmpty)
        XCTAssertTrue(settingsControlSearchResults("nonexistent-setting").isEmpty)
    }

    func testSettingsSearchFindsPagesBySettingNamesAndDescriptions() {
        XCTAssertTrue(SettingsSidebarItem.windows.matchesSearch("fullscreen-width"))
        XCTAssertTrue(SettingsSidebarItem.general.matchesSearch(" LOGIN "))
        XCTAssertTrue(SettingsSidebarItem.sidebar.matchesSearch("clock"))
        XCTAssertTrue(SettingsSidebarItem.shortcuts.matchesSearch("hotkeys"))
        XCTAssertFalse(SettingsSidebarItem.general.matchesSearch("nonexistent-setting"))
        XCTAssertTrue(SettingsSidebarItem.automation.isAdvanced)
        XCTAssertTrue(SettingsSidebarItem.configuration.isAdvanced)
        XCTAssertFalse(SettingsSidebarItem.windows.isAdvanced)
    }

    func testStoredNavigationIdentifiersRestoreAndUnknownValuesFallBack() {
        for page in SettingsSidebarItem.allCases {
            XCTAssertEqual(SettingsSidebarItem.restored(page.rawValue), page)
        }
        for invalid in ["", "removed-page", "General", "999"] {
            XCTAssertEqual(SettingsSidebarItem.restored(invalid), .general)
        }
        XCTAssertEqual(SettingsAutomationSection.restored("events"), .events)
        XCTAssertEqual(SettingsAutomationSection.restored("rules"), .rules)
        XCTAssertEqual(SettingsAutomationSection.restored("removed"), .rules)
    }

    func testShortcutSearchMatchesTitleSubtitleCommandsAndNotation() {
        let focus = ShortcutSettingsModel.Action(id: "focus-left", title: "Focus Left", subtitle: "Select a neighbour", commandScript: "focus left", canonicalCommand: "focus left")
        let split = ShortcutSettingsModel.Action(id: "split-left", title: "Split Left", subtitle: nil, commandScript: "join-with left", canonicalCommand: "join-with left")
        let sections: [ShortcutSettingsModel.Section] = [
            .init(id: "focus", category: .managed, title: "Focus", summary: nil, actions: [focus]),
            .init(id: "splits", category: .managed, title: "Splits", summary: nil, actions: [split]),
        ]
        let assignments = ["focus-left": "alt-h", "split-left": "alt-shift-h"]
        for query in ["FOCUS", "neighbour", " alt-h "] {
            let result = filteredShortcutSections(sections, assignments: assignments, query: query)
            XCTAssertEqual(result.map(\.id), ["focus"])
            XCTAssertEqual(result.flatMap(\.actions).map(\.id), ["focus-left"])
        }
        XCTAssertEqual(filteredShortcutSections(sections, assignments: assignments, query: "JOIN-WITH").flatMap(\.actions), [split])
        XCTAssertEqual(filteredShortcutSections(sections, assignments: assignments, query: "left"), sections)
        XCTAssertTrue(filteredShortcutSections(sections, assignments: assignments, query: "not found").isEmpty)
        XCTAssertEqual(filteredShortcutSections(sections, assignments: assignments, query: " \n"), sections)
        XCTAssertEqual(assignments["focus-left"], "alt-h")
    }

    func testAssignmentPickerKeepsRawWorkspaceIdentityAndDoesNotMoveIt() throws {
        let fixture = WorkspaceNavigationFixture()
        defer { fixture.cleanUp() }
        let before = fixture.displays.map { $0.activeWorkspace.name }
        let focusBefore = focus.workspace.id
        var draft = SettingsAssignmentDraft()
        draft.workspace = "6"
        draft.selector = "main"
        let result = try draft.applying(to: "config-version = 2\n# Keep this comment\n")
        XCTAssertEqual(parseConfig(result).config.workspaceToMonitorForceAssignment["6"], [.main])
        XCTAssertTrue(result.contains("# Keep this comment"))
        XCTAssertEqual(fixture.displays.map { $0.activeWorkspace.name }, before)
        XCTAssertEqual(focus.workspace.id, focusBefore)
    }

    func testUntouchedUnavailableArrayAssignmentPreservesExactBytes() throws {
        let uuid = "11111111-1111-1111-1111-111111111111"
        let text = "config-version = 2\n[workspace-to-monitor-force-assignment]\n'future' = [ 'uuid:\(uuid)', 'main' ] # retain formatting\n"
        let draft = SettingsAssignmentDraft.editing(workspace: "future", selectors: ["uuid:" + uuid, "main"], connectedSelectors: [])
        XCTAssertTrue(draft.advanced)
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(try draft.applying(to: text), text)
    }

    func testConnectedUUIDUsesPickerWithoutChangingAssignment() {
        let selector = "uuid:11111111-1111-1111-1111-111111111111"
        let draft = SettingsAssignmentDraft.editing(workspace: "6", selectors: [selector], connectedSelectors: [selector])
        XCTAssertFalse(draft.advanced)
        XCTAssertEqual(draft.workspace, "6")
        XCTAssertEqual(draft.selector, selector)
        XCTAssertFalse(draft.isDirty)
    }

    func testAssignmentEditRejectsExternalReplacementAndAccidentalOverwrite() throws {
        var draft = SettingsAssignmentDraft.editing(workspace: "one", selectors: ["main"], connectedSelectors: [])
        draft.selector = "uuid:11111111-1111-1111-1111-111111111111"
        let current = "config-version = 2\n[workspace-to-monitor-force-assignment]\none = 2\n"
        XCTAssertThrowsError(try draft.applying(to: current))
        var new = SettingsAssignmentDraft()
        new.workspace = "one"; new.selector = "main"
        XCTAssertThrowsError(try new.applying(to: current))
    }

    func testEditedArrayKeepsOrderAndOtherConfig() throws {
        let text = "config-version = 2\n[workspace-to-monitor-force-assignment]\nfuture = ['main', 'uuid:11111111-1111-1111-1111-111111111111']\n[gaps]\nouter.top = 9\n"
        var draft = SettingsAssignmentDraft.editing(workspace: "future", selectors: ["main", "uuid:11111111-1111-1111-1111-111111111111"], connectedSelectors: [])
        draft.selector = "['uuid:11111111-1111-1111-1111-111111111111', 'main']"
        let updated = try draft.applying(to: text)
        XCTAssertEqual(parseConfig(updated).config.workspaceToMonitorForceAssignment["future"]?.map(\.selector), ["uuid:11111111-1111-1111-1111-111111111111", "main"])
        XCTAssertTrue(updated.contains("[gaps]\nouter.top = 9"))
    }

    func testInvalidAdvancedSelectorsRemainDrafts() {
        for value in ["[]", "[true]", "['main', false]", "hardware:1:2:0", "[", ""] {
            var draft = SettingsAssignmentDraft()
            draft.workspace = "future"; draft.selector = value; draft.advanced = true
            XCTAssertThrowsError(try draft.renderedSelectors(), value)
            XCTAssertEqual(draft.selector, value)
            XCTAssertTrue(draft.isDirty)
        }
    }

    func testRuleRowsSummarizeMatchersAndPreserveCustomActionText() {
        let block = """
        [[on-window-detected]]
        if.app-id = 'com.example.app'
        if.workspace = '6'
        if.during-winmux-startup = true
        run = ['exec-and-forget echo "a;b"', 'layout floating']
        """
        let row = SettingsRuleRow(id: 7, block: block)
        XCTAssertEqual(row.id, 7)
        XCTAssertTrue(row.matches.contains("com.example.app"))
        XCTAssertTrue(row.matches.contains("Workspace 6"))
        XCTAssertTrue(row.matches.contains("Startup"))
        XCTAssertEqual(row.actions, "exec-and-forget echo \"a;b\" → layout floating")
    }

    func testRuleModelRetainsDraftAcrossReadsForPageChanges() {
        let model = SettingsWindowRulesModel(readText: { "[[on-window-detected]]\nrun = 'layout tiling'\n" })
        model.load(); model.select(0)
        model.draft?.titleRegex = "Preferences"
        model.load()
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.selection, 0)
        XCTAssertEqual(model.draft?.titleRegex, "Preferences")
        XCTAssertTrue(model.isDirty)
    }
}
