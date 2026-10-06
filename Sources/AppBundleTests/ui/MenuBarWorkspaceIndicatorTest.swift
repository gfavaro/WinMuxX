@testable import AppBundle
import XCTest

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
}
