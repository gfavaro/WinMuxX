@testable import AppBundle
import AppKit
import XCTest

final class WorkspaceOverviewKeyboardTest: XCTestCase {
    func testGridNavigationAndReverseWindowCycling() {
        XCTAssertEqual(workspaceOverviewKeyAction(keyCode: 123, modifiers: [], hasMarkedText: false), .move(-1))
        XCTAssertEqual(workspaceOverviewKeyAction(keyCode: 125, modifiers: [], hasMarkedText: false), .move(4))
        XCTAssertEqual(workspaceOverviewKeyAction(keyCode: 48, modifiers: [], hasMarkedText: false), .cycleWindow(backward: false))
        XCTAssertEqual(workspaceOverviewKeyAction(keyCode: 48, modifiers: .shift, hasMarkedText: false), .cycleWindow(backward: true))
        XCTAssertEqual(workspaceOverviewKeyAction(keyCode: 36, modifiers: [], hasMarkedText: false), .activate)
        XCTAssertEqual(workspaceOverviewKeyAction(keyCode: 53, modifiers: [], hasMarkedText: false), .dismiss)
        XCTAssertEqual(workspaceOverviewKeyAction(keyCode: 121, modifiers: [], hasMarkedText: false), .page(1))
    }

    func testCompositionAndModifiedEditingCommandsAreNeverIntercepted() {
        for keyCode: UInt16 in [123, 124, 125, 126, 48, 36, 76, 53, 116, 121] {
            XCTAssertNil(workspaceOverviewKeyAction(keyCode: keyCode, modifiers: [], hasMarkedText: true))
            for modifiers: NSEvent.ModifierFlags in [.command, .option, .control] {
                XCTAssertNil(workspaceOverviewKeyAction(keyCode: keyCode, modifiers: modifiers, hasMarkedText: false))
            }
            if keyCode != 48 {
                XCTAssertNil(workspaceOverviewKeyAction(keyCode: keyCode, modifiers: .shift, hasMarkedText: false))
            }
        }
    }
}
