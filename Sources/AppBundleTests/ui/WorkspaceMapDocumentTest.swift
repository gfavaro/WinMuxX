@testable import AppBundle
import TOMLKit
import XCTest

final class WorkspaceMapDocumentTest: XCTestCase {
    private let base = "persistent-workspaces = []\non-window-detected = []\n"

    private func persistent(_ text: String) throws -> [String] {
        try TOMLTable(string: text)["persistent-workspaces"]?.array?.compactMap(\.string) ?? []
    }

    func testAssigningAddsARuleAndKeepsEveryWorkspaceUpToIt() throws {
        let text = try WorkspaceMapDocument.assigning(appId: "com.apple.mail", workspace: 3, in: base)
        XCTAssertEqual(WorkspaceMapDocument.routes(in: text), [WorkspaceMapRoute(appId: "com.apple.mail", workspace: 3, ruleIndex: 0)])
        XCTAssertEqual(try persistent(text), ["1", "2", "3"])
        _ = try TOMLTable(string: text)
    }

    func testAssigningAgainMovesTheSameRuleAndKeepsOnlyAddingPins() throws {
        var text = try WorkspaceMapDocument.assigning(appId: "com.apple.mail", workspace: 3, in: base)
        text = try WorkspaceMapDocument.assigning(appId: "com.apple.mail", workspace: 2, in: text)
        XCTAssertEqual(WorkspaceMapDocument.routes(in: text).map(\.workspace), [2])
        XCTAssertEqual(WorkspaceMapDocument.routes(in: text).count, 1)
        XCTAssertEqual(try persistent(text), ["1", "2", "3"], "A move never drops a pin")
    }

    func testExistingPinsAndTheirNamesSurvive() throws {
        let text = try WorkspaceMapDocument.assigning(
            appId: "com.apple.mail", workspace: 2, in: "persistent-workspaces = [\"5\", \"Notes\"]\n")
        XCTAssertEqual(try persistent(text), ["1", "2", "5", "Notes"])
    }

    func testRemovingTheRuleLeavesThePin() throws {
        var text = try WorkspaceMapDocument.assigning(appId: "com.apple.mail", workspace: 3, in: base)
        text = try WorkspaceMapDocument.removing(appId: "com.apple.mail", in: text)
        XCTAssertTrue(WorkspaceMapDocument.routes(in: text).isEmpty)
        XCTAssertEqual(WorkspaceMapDocument.pinned(in: text), [1, 2, 3])
    }

    func testUnpinningIsRefusedWhileAnAppIsRoutedThereOrLater() throws {
        let text = try WorkspaceMapDocument.assigning(appId: "com.apple.mail", workspace: 3, in: base)
        XCTAssertThrowsError(try WorkspaceMapDocument.unpinning(workspace: 3, in: text))
        XCTAssertThrowsError(try WorkspaceMapDocument.unpinning(workspace: 2, in: text))
        let freed = try WorkspaceMapDocument.removing(appId: "com.apple.mail", in: text)
        XCTAssertEqual(WorkspaceMapDocument.pinned(in: try WorkspaceMapDocument.unpinning(workspace: 3, in: freed)), [1, 2])
    }

    func testOnlySimpleRulesAreRoutes() throws {
        let text = """
        [[on-window-detected]]
        if.app-id = "com.apple.finder"
        run = 'layout floating'

        [[on-window-detected]]
        if.app-id = "com.apple.mail"
        if.window-title-regex-substring = "Inbox"
        run = ['move-node-to-workspace "2"']

        [[on-window-detected]]
        if.app-id = "com.apple.Safari"
        run = ['move-node-to-workspace "4"']
        """
        XCTAssertEqual(WorkspaceMapDocument.routes(in: text), [WorkspaceMapRoute(appId: "com.apple.Safari", workspace: 4, ruleIndex: 2)])
    }

    func testAnEarlierStoppingRuleForTheAppIsReportedInsteadOfShadowingTheNewOne() {
        let text = "[[on-window-detected]]\nif.app-id = \"com.apple.mail\"\nrun = 'layout floating'\n"
        XCTAssertThrowsError(try WorkspaceMapDocument.assigning(appId: "com.apple.mail", workspace: 2, in: text))
    }

    func testOtherRulesAndCommentsAreLeftAlone() throws {
        let text = "# keep me\n[[on-window-detected]]\nif.app-id = \"com.apple.finder\"\nrun = 'layout floating'\n"
        let result = try WorkspaceMapDocument.assigning(appId: "com.apple.mail", workspace: 1, in: text)
        XCTAssertTrue(result.contains(text), "The existing comment and rule stay as written")
        XCTAssertEqual(try persistent(result), ["1"])
        XCTAssertEqual(WorkspaceMapDocument.routes(in: result).map(\.appId), ["com.apple.mail"])
    }
}
