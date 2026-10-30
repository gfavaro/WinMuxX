@testable import AppBundle
import Common
import XCTest

@MainActor
final class WindowRuleDialogTest: XCTestCase {
    private func commands(_ scripts: [String]) throws -> [any Command] {
        try scripts.map { try XCTUnwrap(parseCommand($0).cmdOrNil) }
    }

    func testRoutingRulesSkipDialogsButFloatingStillApplies() throws {
        // WinMux issue #23: an app-wide routing rule sent the app's Save panel to another workspace.
        let rule = try commands(["layout floating", "move-node-to-workspace 4", "move-node-to-monitor next"])
        XCTAssertEqual(windowRuleCommands(rule, isDialog: false).count, 3, "Ordinary windows are routed")
        let forDialog = windowRuleCommands(rule, isDialog: true)
        XCTAssertEqual(forDialog.count, 1)
        XCTAssertTrue(forDialog.first is LayoutCommand, "A dialog still floats")
        XCTAssertTrue(isWindowRelocation(try XCTUnwrap(parseCommand("move-node-to-workspace 2").cmdOrNil)))
        XCTAssertFalse(isWindowRelocation(try XCTUnwrap(parseCommand("layout tiling").cmdOrNil)))
    }
}
