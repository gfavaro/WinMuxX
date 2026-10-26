import XCTest
@testable import AppBundle
import TOMLKit

final class QuickFloatingRuleTest: XCTestCase {
    func testRuleEscapesBundleAndAnchorsLiteralTitle() throws {
        let block = QuickFloatingRuleDocument.rule(bundleId: "com.example.app", match: .exactTitle("Save [draft] $1"))
        let table = try TOMLTable(string: block)
        let rule = try XCTUnwrap(table["on-window-detected"]?.array?.first?.table)
        XCTAssertEqual(rule["if"]?.table?["app-id"]?.string, "com.example.app")
        XCTAssertEqual(rule["if"]?.table?["window-title-regex-substring"]?.string, "^Save \\[draft] \\$1$")
        XCTAssertEqual(rule["run"]?.string, "layout floating")
    }

    func testStoppingCallbackForAppBlocksQuickSaveAndReportsItsActions() {
        let text = """
        [[on-window-detected]]
        if.app-id = 'com.example.app'
        run = ['layout tiling', 'workspace Work']
        """
        XCTAssertEqual(
            QuickFloatingRuleDocument.conflict(in: text, bundleId: "com.example.app", appName: "Example", title: "Document"),
            QuickFloatingRuleConflict(ruleIndex: 0, actions: ["layout tiling", "workspace Work"])
        )
    }

    func testContinuingCallbackDoesNotBlockQuickSave() {
        let text = """
        [[on-window-detected]]
        if.app-id = 'com.example.app'
        check-further-callbacks = true
        run = 'layout tiling'
        """
        XCTAssertNil(QuickFloatingRuleDocument.conflict(in: text, bundleId: "com.example.app", appName: nil, title: nil))
    }

    func testAppSpecificNonmatchingRuleDoesNotConflict() {
        let text = """
        [[on-window-detected]]
        if.app-id = 'com.other.app'
        run = 'layout tiling'
        """
        XCTAssertNil(QuickFloatingRuleDocument.conflict(in: text, bundleId: "com.example.app", appName: nil, title: nil))
    }
}
