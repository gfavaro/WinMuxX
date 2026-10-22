@testable import AppBundle
import Common
import XCTest

@MainActor final class SettingsModeAutosaveTest: WorkspaceTestCase {
    func testModeCreationAndOptionsPreserveQuotedNamesAndBindings() throws {
        let original = """
        # keep my custom entry
        [mode.main.binding]
        alt-space = 'mode nav.dot'
        [mode."nav.dot".binding]
        esc = 'mode main'
        h = 'focus left'
        """
        let created = try addingSettingsMode("Move ✨", to: original)
        let changed = applyingSettingsConfigEdits([
            .init(section: "mode.\"nav.dot\"", key: "timeout-ms", renderedValue: "1500"),
            .init(section: "mode.\"nav.dot\"", key: "show-indicator", renderedValue: "true"),
            .init(section: "mode.\"nav.dot\"", key: "exit-on-unbound-key", renderedValue: "true"),
            .init(section: "mode.\"nav.dot\"", key: "indicator-color", renderedValue: "'#5E9EFF'"),
        ], to: created)
        let parsed = parseConfig(changed)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.modes["nav.dot"]?.timeoutMs, 1500)
        XCTAssertEqual(parsed.config.modes["nav.dot"]?.showIndicator, true)
        XCTAssertEqual(parsed.config.modes["nav.dot"]?.exitOnUnboundKey, true)
        XCTAssertEqual(parsed.config.modes["nav.dot"]?.bindings.count, 2)
        XCTAssertEqual(parsed.config.modes["Move ✨"]?.timeoutMs, 0)
        XCTAssertEqual(parsed.config.modes["Move ✨"]?.bindings.values.first?.commands.prettyDescription, "mode main")
        XCTAssertTrue(changed.contains("# keep my custom entry"))
        XCTAssertTrue(parseConfig(try addingSettingsMode("first", to: "")).errors.isEmpty)
        XCTAssertThrowsError(try updatingSettingsMode("deleted", key: "timeout-ms", value: "1500", in: changed))
        XCTAssertEqual(parseConfig(try updatingSettingsMode("nav.dot", key: "timeout-ms", value: "2000", in: changed)).config.modes["nav.dot"]?.timeoutMs, 2000)
        XCTAssertThrowsError(try addingSettingsMode("main", to: changed))
        XCTAssertThrowsError(try addingSettingsMode("\n", to: changed))
        let restored = applyingSettingsConfigEdits([.init(section: "mode.\"nav.dot\"", key: "indicator-color", renderedValue: nil)], to: changed)
        XCTAssertNil(parseConfig(restored).config.modes["nav.dot"]?.indicatorColor)
    }

    func testRuleAutosavePreservesEditsMadeDuringReloadAndRebasesNextWrite() async throws {
        var text = "[[on-window-detected]]\nrun = 'layout tiling'\n[on-window-detected.if]\napp-id = 'old.app'\n"
        let rules = SettingsWindowRulesModel(readText: { text })
        var writes = 0
        let second = expectation(description: "second edit saved")
        let access = SettingsConfigAccess(edit: { transform in
            text = try transform(text)
            XCTAssertTrue(parseConfig(text).errors.isEmpty)
            writes += 1
            return URL(filePath: "/unused")
        }, reload: { _ in
            config = parseConfig(text).config
            if writes == 1 { rules.draft?.appRegex = "new-app" }
            if writes == 2 { second.fulfill() }
            return true
        })
        let model = ShortcutSettingsModel(configAccess: access, drafts: SettingsDraftStore())
        rules.load(); rules.select(0)
        rules.draft?.appId = "new.app"
        rules.autosave(using: model)
        rules.autosave(using: model) // suppress duplicate submissions
        await fulfillment(of: [second], timeout: 2)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(writes, 2)
        XCTAssertFalse(rules.isSaving)
        XCTAssertFalse(rules.isDirty)
        XCTAssertTrue(text.contains("new.app"))
        XCTAssertTrue(text.contains("new-app"))
    }

    func testFailedAutosaveRetainsRuleAndDoesNotRetryForever() async {
        let original = "[[on-window-detected]]\nrun = 'layout tiling'\n"
        let rules = SettingsWindowRulesModel(readText: { original })
        var attempts = 0
        let completed = expectation(description: "failure handled")
        let model = ShortcutSettingsModel(configAccess: .init(edit: { _ in
            attempts += 1
            throw SettingsDisplayError("Disk unavailable")
        }, reload: { _ in true }), drafts: SettingsDraftStore())
        rules.load(); rules.select(0); rules.draft?.appId = "new.app"
        rules.autosave(using: model)
        model.saveQueue.enqueue { completed.fulfill() }
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertFalse(rules.isSaving)
        XCTAssertTrue(rules.isDirty)
        XCTAssertEqual(rules.draft?.appId, "new.app")
        XCTAssertNotNil(model.retrySettingsSave)
        for _ in 0..<10 { rules.autosave(using: model) }
        XCTAssertEqual(attempts, 1)
    }
}
