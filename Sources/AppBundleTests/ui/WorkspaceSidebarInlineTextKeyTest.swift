@testable import AppBundle
import AppKit
import XCTest

final class WorkspaceSidebarInlineTextKeyTest: XCTestCase {
    func testNavigationKeysMatchAcrossEventSources() throws {
        let cases: [(UInt16, WorkspaceSidebarInlineTextKey)] = [
            (36, .commit), (76, .commit), (53, .cancel), (51, .deleteBackward),
            (117, .deleteForward), (126, .moveUp), (125, .moveDown),
        ]
        for (keyCode, expected) in cases {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: keyCode,
            ))
            let cgEvent = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
            // CGEvent inherits the live keyboard state unless flags are set explicitly.
            cgEvent.flags = []
            XCTAssertEqual(workspaceSidebarInlineTextKey(from: event), expected)
            XCTAssertEqual(workspaceSidebarInlineTextKey(from: cgEvent), expected)
        }
    }

    func testCommandDeleteTakesPriorityOverOptionDelete() {
        XCTAssertEqual(parse(51, [.command, .option], ""), .deleteToBeginningOfLine)
        XCTAssertEqual(parse(51, [.option], ""), .deleteWordBackward)
        XCTAssertEqual(parse(51, [.control], ""), .deleteBackward)
    }

    func testTextAcceptsUnicodeAndShiftButRejectsShortcutsAndControlCharacters() {
        XCTAssertEqual(parse(0, [.shift], "Á🙂"), .text("Á🙂"))
        for modifiers: NSEvent.ModifierFlags in [.command, .option, .control] {
            XCTAssertEqual(parse(0, modifiers, "a"), .ignored)
        }
        for text in ["", "\n", "a\t"] {
            XCTAssertEqual(parse(0, [], text), .ignored)
        }
        XCTAssertEqual(workspaceSidebarInlineTextKey(keyCode: 0, modifiers: [], text: { nil }), .ignored)
    }

    func testNavigationAndShortcutsDoNotReadText() {
        var reads = 0
        let text = { reads += 1; return "a" as String? }
        XCTAssertEqual(workspaceSidebarInlineTextKey(keyCode: 36, modifiers: [], text: text), .commit)
        XCTAssertEqual(workspaceSidebarInlineTextKey(keyCode: 0, modifiers: [.command], text: text), .ignored)
        XCTAssertEqual(reads, 0)
    }

    private func parse(_ keyCode: Int64, _ modifiers: NSEvent.ModifierFlags, _ text: String) -> WorkspaceSidebarInlineTextKey {
        workspaceSidebarInlineTextKey(keyCode: keyCode, modifiers: modifiers, text: { text })
    }
}
