@testable import AppBundle
import XCTest

@MainActor
final class ShortcutFailureNoticeTest: XCTestCase {
    func testOnlyFailuresWithAMessageShowANotice() {
        let marker = UUID().uuidString
        NoticePanel.shared.show(title: marker, body: "")
        showShortcutFailure("alt-h", CmdResult(stdout: [], stderr: [], exitCode: 1))
        showShortcutFailure("alt-h", CmdResult(stdout: [], stderr: ["ignored"], exitCode: 0))
        XCTAssertEqual(NoticePanel.shared.lastNotice?.title, marker, "A silent no-op and a success show nothing")
        showShortcutFailure("alt-1", CmdResult(stdout: [], stderr: ["", "Desktop 9 does not exist"], exitCode: 1))
        XCTAssertEqual(NoticePanel.shared.lastNotice?.title, "alt-1 did not run")
        XCTAssertEqual(NoticePanel.shared.lastNotice?.body, "Desktop 9 does not exist")
    }
}
