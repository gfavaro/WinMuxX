@testable import AppBundle
import AppKit
import SwiftUI
import XCTest

@MainActor
final class PaletteNativeControlsTest: XCTestCase {
    func testNativeEditingAndCompositionKeepTheirCommands() {
        var query = "old"
        var commands: [PaletteSearchCommand] = []
        let search = PaletteSearchField(text: Binding(get: { query }, set: { query = $0 }),
            onCommand: { commands.append($0) })
        let coordinator = search.makeCoordinator()
        let field = NSSearchField(), editor = NSTextView()
        editor.string = "committed"
        for selector in [#selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)),
                         #selector(NSResponder.selectAll(_:)), #selector(NSTextView.paste(_:)),
                         #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:))] {
            XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: selector))
        }
        XCTAssertTrue(commands.isEmpty)
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(overlayHasMarkedText(editor))
        for selector in [#selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)),
                         #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
            XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: selector))
        }
        XCTAssertEqual(query, "old")
        XCTAssertTrue(commands.isEmpty)
        editor.unmarkText()
        XCTAssertFalse(overlayHasMarkedText(editor))
        editor.string = "committed"
        for selector in [#selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)),
                         #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
            XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: selector))
        }
        XCTAssertEqual(commands, [.previous, .next, .activate, .dismiss])
        XCTAssertEqual(query, "committed")
    }

    func testClearButtonSyncsQueryAndDismantlingRejectsLateEvents() {
        var query = "text"
        var calls = 0
        let search = PaletteSearchField(text: Binding(get: { query }, set: { query = $0 }),
            onCommand: { _ in calls += 1 })
        let coordinator = search.makeCoordinator()
        let field = NativeSearchField()
        coordinator.searchChanged(field)
        XCTAssertEqual(query, "")
        PaletteSearchField.dismantleNSView(field, coordinator: coordinator)
        field.stringValue = "late"
        coordinator.searchChanged(field)
        XCTAssertEqual(query, "")
        XCTAssertFalse(coordinator.control(field, textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(calls, 0)
        XCTAssertNil(field.delegate)
        XCTAssertNil(field.target)
        XCTAssertNil(field.onAttach)
    }

    func testQuickSelectRequiresExactShortcutAndYieldsToComposition() {
        for digit in 1...9 {
            XCTAssertEqual(paletteQuickSelectIndex(characters: String(digit), modifiers: .command, hasMarkedText: false), digit - 1)
            XCTAssertNil(paletteQuickSelectIndex(characters: String(digit), modifiers: .command, hasMarkedText: true))
        }
        for modifiers: NSEvent.ModifierFlags in [[], [.command, .shift], [.command, .control], [.command, .option]] {
            XCTAssertNil(paletteQuickSelectIndex(characters: "1", modifiers: modifiers, hasMarkedText: false))
        }
        for characters in [nil, "0", "x", "10"] {
            XCTAssertNil(paletteQuickSelectIndex(characters: characters, modifiers: .command, hasMarkedText: false))
        }
    }
}
