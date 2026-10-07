@testable import AppBundle
import AppKit
import SwiftUI
import XCTest

@MainActor
final class WorkspaceSidebarSearchFieldTest: XCTestCase {
    func testNativeEditingCommandsAreNotConsumedByResultNavigation() {
        var query = "hello world"
        var commands: [WorkspaceSidebarInlineTextKey] = []
        let view = WorkspaceSidebarSearchField(
            text: Binding(get: { query }, set: { query = $0 }),
            requestsFocus: false,
            onEditorReady: { _ in },
            onCommand: { commands.append($0) }
        )
        let coordinator = view.makeCoordinator()
        let field = NSSearchField()
        let editor = NSTextView()
        editor.string = query
        for selector in [#selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)),
                         #selector(NSResponder.selectAll(_:)), #selector(NSTextView.paste(_:)),
                         #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:))] {
            XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: selector))
        }
        XCTAssertTrue(commands.isEmpty)

        // Replacing a selection is handled by AppKit, then synced to the query.
        editor.selectedRange = NSRange(location: 6, length: 5)
        editor.insertText("macOS", replacementRange: editor.selectedRange)
        field.stringValue = editor.string
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(query, "hello macOS")
    }

    func testSearchNavigationCommitsAndCancelsWithoutTakingOverComposition() {
        var query = ""
        var commands: [WorkspaceSidebarInlineTextKey] = []
        let view = WorkspaceSidebarSearchField(
            text: Binding(get: { query }, set: { query = $0 }), requestsFocus: false,
            onEditorReady: { _ in }, onCommand: { commands.append($0) }
        )
        let coordinator = view.makeCoordinator()
        let field = NSSearchField()
        let editor = NSTextView()
        editor.string = "terminal"
        for selector in [#selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)),
                         #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
            XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: selector))
        }
        XCTAssertEqual(commands, [.moveUp, .moveDown, .commit, .cancel])
        XCTAssertEqual(query, "terminal")
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(commands.count, 4)

        field.stringValue = ""
        coordinator.searchChanged(field)
        XCTAssertEqual(query, "")
    }
}
