@testable import AppBundle
import XCTest

@MainActor
final class MenuBarWorkspaceIndicatorTest: XCTestCase {
    func testUnlabeledWorkspaceUsesEntireNumber() {
        XCTAssertEqual(menuBarWorkspaceIndicator(label: nil, number: 1), "1")
        XCTAssertEqual(menuBarWorkspaceIndicator(label: "", number: 12), "12")
        XCTAssertEqual(menuBarWorkspaceIndicator(label: " \n ", number: 3), "3")
    }

    func testLabelInitialPreservesUnicodeAndIgnoresSurroundingWhitespace() {
        XCTAssertEqual(menuBarWorkspaceIndicator(label: " desenvolvimento ", number: 2), "D")
        XCTAssertEqual(menuBarWorkspaceIndicator(label: "área de trabalho", number: 2), "Á")
        XCTAssertEqual(menuBarWorkspaceIndicator(label: "👩🏽‍💻 Trabalho", number: 2), "👩🏽‍💻")
    }

    func testAllDisplaysIsAValidIndicator() {
        let parsed = parseConfig("[menu-bar]\nindicator = 'all-displays'")
        XCTAssertTrue(parsed.errors.isEmpty)
        XCTAssertEqual(parsed.config.menuBar.indicator, .allDisplays)
        XCTAssertFalse(parseConfig("[menu-bar]\nindicator = 'everything'").errors.isEmpty)
    }

    func testTheMainDisplayComesFirstThenTheOthersInOrder() {
        XCTAssertEqual(mainDisplayFirst([1, 2, 3, 4], isMain: { $0 == 3 }), [3, 1, 2, 4])
        XCTAssertEqual(mainDisplayFirst([1, 2], isMain: { $0 == 1 }), [1, 2])
        XCTAssertEqual(mainDisplayFirst([7], isMain: { _ in false }), [7])
    }
}
