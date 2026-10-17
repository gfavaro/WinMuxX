@testable import AppBundle
import Common
import TOMLKit
import XCTest

@MainActor
final class SettingsEditorsTest: WorkspaceTestCase {

    func testHardwareSelectorsRejectInvalidOrIncompleteIdentities() throws {
        let identity = try XCTUnwrap(MonitorHardwareIdentity(vendor: 123, model: 456, serial: 789))
        XCTAssertEqual(parseMonitorDescription("HARDWARE:123:456:789").getOrNil(), .hardware(identity))
        XCTAssertEqual(MonitorDescription.hardware(identity).selector, "hardware:123:456:789")
        for value in ["hardware:1:2", "hardware:1:2:0", "hardware:-1:2:3", "hardware:1:x:3", "hardware:4294967296:2:3", "hardware:1:2:3:4"] {
            XCTAssertNil(parseMonitorDescription(value).getOrNil(), value)
        }
    }

    func testHardwareResolutionRequiresExactlyOneMatch() throws {
        let identity = try XCTUnwrap(MonitorHardwareIdentity(vendor: 1, model: 2, serial: 3))
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 800)
        let a = TestMonitor(hardwareIdentity: identity, monitorAppKitNsScreenScreensId: 1, name: "Same", rect: rect, visibleRect: rect, isMain: true)
        let b = TestMonitor(hardwareIdentity: identity, monitorAppKitNsScreenScreensId: 2, name: "Same", rect: rect, visibleRect: rect, isMain: false)
        let selector = MonitorDescription.hardware(identity)
        XCTAssertNotNil(selector.resolveMonitor(sortedMonitors: [a]))
        XCTAssertNil(selector.resolveMonitor(sortedMonitors: [a, b]))
        XCTAssertNil(selector.resolveMonitor(sortedMonitors: []))
    }

    func testSelectorFormattingSurvivesExistingConfigWriters() throws {
        let selector = "hardware:1:2:3"
        let text = "config-version = 2\ngaps.inner.horizontal = [{ monitor.'\(selector)' = 8 }, 4]"
        let parsed = parseConfig(text)
        XCTAssertTrue(parsed.errors.isEmpty, parsed.errors.description)
        XCTAssertTrue(settingsGapValue(parsed.config.gaps.inner.horizontal, replacingDefaultWith: 5).contains(selector))
    }

    func testRuleBoundariesIgnoreHeadersInMultilineStrings() throws {
        let text = """
        config-version = 2
        [[on-window-detected]] # first
        if.app-id = 'com.example.one'
        run = '''exec-and-forget echo '
        [[on-window-detected]]
        [fake]
        '
        '''
        [[on-window-detected]]
        run = 'layout floating'
        [gaps]
        outer.top = 8
        """
        let doc = SettingsRuleDocument(text)
        XCTAssertEqual(doc.entries.count, 2)
        XCTAssertTrue(doc.entries[0].text.contains("[fake]"))
        XCTAssertFalse(doc.entries[1].text.contains("[gaps]"))
        let updated = try doc.replacing(1, with: nil, in: text)
        XCTAssertTrue(updated.contains("[gaps]\nouter.top = 8"))
        XCTAssertEqual(SettingsRuleDocument(updated).entries.count, 1)
    }

    func testRuleEditsPreserveCustomActionsCommentsAndOtherTables() throws {
        let block = """
        [[on-window-detected]] # rule header
        # Keep this comment
        run = ['exec-and-forget echo "a;b"', 'layout floating'] # custom
        [on-window-detected.if] # match header
        app-id = 'com.example.old'

        """
        let updated = try SettingsRuleDocument.editing(block, edits: [
            .init(section: "if", key: "app-id", renderedValue: "'com.example.new'"),
            .init(section: nil, key: "check-further-callbacks", renderedValue: "true"),
        ])
        XCTAssertTrue(updated.hasPrefix("[[on-window-detected]] # rule header"))
        XCTAssertTrue(updated.contains("run = ['exec-and-forget echo \"a;b\"', 'layout floating'] # custom"))
        XCTAssertTrue(updated.contains("[on-window-detected.if] # match header"))
        XCTAssertTrue(updated.contains("# Keep this comment"))
        let row = try XCTUnwrap(TOMLTable(string: updated)["on-window-detected"]?.array?.first?.table)
        XCTAssertEqual(row["if"]?.table?["app-id"]?.string, "com.example.new")
        XCTAssertEqual(row["check-further-callbacks"]?.bool, true)
    }

    func testRuleEditAllowsUnrelatedExternalChangeButRejectsRuleChange() throws {
        let text = "config-version = 2\n[[on-window-detected]]\nrun = 'layout floating'\n[gaps]\nouter.top = 8"
        let baseline = SettingsRuleDocument(text)
        let changed = text.replacingOccurrences(of: "outer.top = 8", with: "outer.top = 9")
        let edited = try baseline.replacing(0, with: "[[on-window-detected]]\nrun = 'layout tiling'\n", in: changed)
        XCTAssertTrue(edited.contains("outer.top = 9"))
        XCTAssertThrowsError(try baseline.replacing(0, with: nil, in: text.replacingOccurrences(of: "floating", with: "tiling")))
    }

    func testRuleReorderingPreservesExactEntries() throws {
        let text = "[[on-window-detected]] # A\nrun = 'layout floating'\n[[on-window-detected]] # B\nrun = 'layout tiling'\n"
        let baseline = SettingsRuleDocument(text)
        let result = try baseline.moving(1, by: -1, in: text)
        XCTAssertEqual(SettingsRuleDocument(result).entries.map(\.text), baseline.entries.reversed().map(\.text))
        XCTAssertThrowsError(try baseline.moving(0, by: -1, in: text))
        XCTAssertThrowsError(try baseline.moving(0, by: 1, in: result))
    }

    func testGuidedActionsOnlyAcceptRepresentableOrderedCommands() throws {
        XCTAssertNotNil(GuidedRuleActions(commands: ["layout floating", "move-node-to-workspace 'two-words'"]))
        XCTAssertNil(GuidedRuleActions(commands: ["move-node-to-workspace 2", "layout floating"]))
        XCTAssertNil(GuidedRuleActions(commands: ["layout floating", "layout tiling"]))
        XCTAssertNil(GuidedRuleActions(commands: ["exec-and-forget echo 'a;b'"]))
        XCTAssertNil(GuidedRuleActions(commands: ["move-node-to-workspace next"]))
        XCTAssertNil(GuidedRuleActions(commands: ["layout --for-next-detected-window floating"]))
    }

    func testMatcherEditDoesNotRewriteCustomRunArray() throws {
        let block = "[[on-window-detected]]\nrun = ['exec-and-forget echo a;b', 'layout tiling']\n"
        let original = try SettingsRuleDraft(block: block)
        XCTAssertNil(original.guided)
        var draft = original
        draft.titleRegex = "Preferences"
        let edits = draft.edits(from: original)
        XCTAssertEqual(edits.count, 1)
        XCTAssertEqual(edits[0].key, "window-title-regex-substring")
        let edited = try SettingsRuleDocument.editing(block, edits: edits)
        XCTAssertTrue(edited.contains("run = ['exec-and-forget echo a;b', 'layout tiling']"))
        XCTAssertTrue(parseConfig(edited).errors.isEmpty)
    }

    func testInvalidRegexIsRejectedBeforeWriting() throws {
        let block = "[[on-window-detected]]\nrun = 'layout tiling'\n"
        let edited = try SettingsRuleDocument.editing(block, edits: [.init(section: "if", key: "window-title-regex-substring", renderedValue: "'['")])
        XCTAssertFalse(parseConfig(edited).errors.isEmpty)
    }

    func testNewRuleRemainsAnUnsavedDraft() {
        let model = SettingsWindowRulesModel(readText: { "config-version = 2" })
        model.add()
        XCTAssertTrue(model.isNewRule)
        XCTAssertTrue(model.isDirty)
        model.revert()
        XCTAssertFalse(model.isDirty)
        XCTAssertFalse(model.isNewRule)
    }

    func testDisplaysSnapshotDoesNotMoveOrCreateWorkspaces() {
        let before = Workspace.all.map { ($0.name, $0.workspaceMonitor.name) }
        let focusBefore = focus.workspace.id
        SettingsDisplaysModel().refresh()
        XCTAssertEqual(Workspace.all.map(\.name), before.map(\.0))
        XCTAssertEqual(Workspace.all.map { $0.workspaceMonitor.name }, before.map(\.1))
        XCTAssertEqual(focus.workspace.id, focusBefore)
    }

    func testDisconnectedDisplayMoveDoesNotMutateState() async {
        let before = focus.workspace.id
        do {
            try await SettingsDisplaysModel().bringHere(workspace: focus.workspace.name, selector: "uuid:11111111-1111-1111-1111-111111111111")
            XCTFail("Expected missing display error")
        } catch {}
        XCTAssertEqual(focus.workspace.id, before)
    }

    func testExplicitMovesToEachSecondaryPreserveOtherDisplays() async throws {
        let displays = (0..<4).map { index in
            let rect = Rect(topLeftX: Double(index * 1000), topLeftY: 0, width: 1000, height: 800)
            return TestMonitor(displayUUID: "00000000-0000-0000-0000-00000000000\(index + 1)",
                               monitorAppKitNsScreenScreensId: index + 1, name: "Display\(index + 1)",
                               rect: rect, visibleRect: rect, isMain: index == 0)
        }
        setMonitorsForTests(displays)
        let spaces = (1...6).map { Workspace.get(byName: String($0)) }
        for (index, workspace) in spaces.enumerated() {
            workspace.seedMonitorIfNeeded(displays[0])
            TestWindow.new(id: UInt32(9800 + index), parent: workspace.rootTilingContainer).markAsMostRecentChild()
        }
        for (index, display) in displays.enumerated() { XCTAssertTrue(display.setActiveWorkspace(spaces[index])) }
        XCTAssertTrue(spaces[0].focusWorkspace())
        for index in 1..<4 {
            let before = displays.map { $0.activeWorkspace.name }
            let old = displays[index].activeWorkspace
            try await SettingsDisplaysModel().bringHere(workspace: spaces[4].name, selector: "uuid:" + displays[index].displayUUID!)
            XCTAssertEqual(displays[index].activeWorkspace, spaces[4])
            XCTAssertEqual(focus.workspace, spaces[4])
            XCTAssertEqual(old.workspaceMonitor.rect, displays[0].rect)
            for other in 1..<4 where other != index {
                // Leaving a display whose workspace is moved creates a replacement there;
                // displays unrelated to source and destination must stay unchanged.
                if before[other] != spaces[4].name { XCTAssertEqual(displays[other].activeWorkspace.name, before[other]) }
            }
        }
    }

    func testChangedDestinationConfirmationDoesNotMoveWorkspace() async throws {
        let fixture = WorkspaceNavigationFixture()
        defer { fixture.cleanUp() }
        let before = fixture.displays.map { $0.activeWorkspace.name }
        do {
            try await SettingsDisplaysModel().bringHere(workspace: fixture.spaces[0].name, selector: "2", expectedVisibleWorkspace: "no-longer-visible")
            XCTFail("Expected a stale confirmation error")
        } catch {}
        XCTAssertEqual(fixture.displays.map { $0.activeWorkspace.name }, before)
        XCTAssertEqual(focus.workspace, fixture.spaces[0])
    }

    func testSavedAssignmentsRejectMultipleWorkspacesOnSecondary() throws {
        let fixture = WorkspaceNavigationFixture()
        defer { fixture.cleanUp() }
        XCTAssertThrowsError(try validateSecondarySettingsAssignments("""
        config-version = 2
        [workspace-to-monitor-force-assignment]
        one = 2
        two = 2
        """))
        XCTAssertNoThrow(try validateSecondarySettingsAssignments("""
        config-version = 2
        [workspace-to-monitor-force-assignment]
        one = 1
        two = 1
        three = 2
        """))
    }

    func testInvalidRuleDraftSurvivesReloadAndSelectionChange() throws {
        let model = SettingsWindowRulesModel(readText: {
            "config-version = 2\n[[on-window-detected]]\nrun = 'layout tiling'\n[[on-window-detected]]\nrun = 'layout floating'\n"
        })
        model.load()
        model.select(0)
        model.draft?.titleRegex = "["
        model.load()
        model.select(1)
        XCTAssertEqual(model.selection, 0)
        XCTAssertEqual(model.draft?.titleRegex, "[")
        XCTAssertTrue(model.isDirty)
        model.revert()
        XCTAssertFalse(model.isDirty)
    }

    func testQuotedStringsRoundTripControlsAndUnicode() throws {
        let raw = "Quote \" slash / newline\n tab\t Unicode 日本語"
        XCTAssertEqual(try TOMLTable(string: "value = " + settingsQuotedString(raw))["value"]?.string, raw)
    }
}
