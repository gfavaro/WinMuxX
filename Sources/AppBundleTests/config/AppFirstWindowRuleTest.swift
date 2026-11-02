@testable import AppBundle
import Common
import XCTest

/// Helium's rule sent every new window to workspace 5, including its login pop-up, which pushed
/// workspace 4 off the secondary display. `if.app-has-other-windows = false` limits a rule to the
/// window an app opens when it launches.
@MainActor
final class AppFirstWindowRuleTest: XCTestCase {
    override func tearDown() async throws { setUpWorkspacesForTests() }

    private func rule(_ value: Bool) -> WindowDetectedCallback {
        let parsed = parseConfig("""
        [[on-window-detected]]
        if.app-has-other-windows = \(value)
        run = 'move-node-to-workspace 5'
        """)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        return parsed.config.onWindowDetected[0]
    }

    func testFirstWindowMatchesAndALaterWindowOfTheSameAppDoesNot() async throws {
        setUpWorkspacesForTests()
        let workspace = focus.workspace
        let main = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let firstOnly = rule(false), laterOnly = rule(true)
        let isFirst = try await firstOnly.matches(main)
        XCTAssertTrue(isFirst, "The app's only window is its first window")
        let firstIsLater = try await laterOnly.matches(main)
        XCTAssertFalse(firstIsLater)

        let popup = TestWindow.new(id: 2, parent: workspace)
        let popupIsFirst = try await firstOnly.matches(popup)
        XCTAssertFalse(popupIsFirst, "A login window opened while the app has a window is not its first")
        let popupIsLater = try await laterOnly.matches(popup)
        XCTAssertTrue(popupIsLater)
    }

    func testAMinimizedWindowOfTheAppStillCounts() async throws {
        setUpWorkspacesForTests()
        _ = TestWindow.new(id: 1, parent: macosMinimizedWindowsContainer)
        let later = TestWindow.new(id: 2, parent: focus.workspace.rootTilingContainer)
        let laterIsFirst = try await rule(false).matches(later)
        XCTAssertFalse(laterIsFirst, "The app's main window is only minimized, so this is not its first window")
        let laterIsAdditional = try await rule(true).matches(later)
        XCTAssertTrue(laterIsAdditional)
    }

    func testRejectsANonBooleanValue() {
        let parsed = parseConfig("[[on-window-detected]]\nif.app-has-other-windows = 'no'\nrun = 'layout floating'")
        XCTAssertFalse(parsed.errors.isEmpty)
    }

    func testSettingsEditorReadsAndWritesTheCondition() throws {
        let block = "[[on-window-detected]]\nif.app-id = 'net.imput.helium'\nrun = 'move-node-to-workspace 5'\n"
        let original = try SettingsRuleDraft(block: block)
        XCTAssertEqual(original.appWindows, "any")
        var draft = original
        draft.appWindows = "first"
        let edited = try SettingsRuleDocument.editing(block, edits: draft.edits(from: original))
        XCTAssertTrue(edited.contains("app-has-other-windows = false"), edited)
        XCTAssertTrue(parseConfig(edited).errors.isEmpty)
        XCTAssertEqual(try SettingsRuleDraft(block: edited).appWindows, "first")
        XCTAssertEqual(SettingsRuleRow(id: 0, block: edited).matches, "net.imput.helium · First window")
    }
}
