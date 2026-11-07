@testable import AppBundle
import AppKit
import XCTest

final class SystemShortcutsTest: XCTestCase {
    private func entry(enabled: Bool, keyCode: Int, mask: Int) -> [String: Any] {
        ["enabled": NSNumber(value: enabled), "value": ["parameters": [NSNumber(value: 65535), NSNumber(value: keyCode), NSNumber(value: mask)], "type": "standard"]]
    }

    func testDefaultsApplyUntilTheUserChangesThem() {
        let shortcuts = SystemShortcuts.enabled(overrides: [
            "64": ["enabled": NSNumber(value: false)],
            "80": entry(enabled: true, keyCode: 123, mask: 0x40000 | 0x20000 | 0x800000),
            "32": entry(enabled: true, keyCode: 126, mask: 0x40000 | 0x80000),
        ])
        XCTAssertNil(shortcuts.first { $0.id == 64 }, "A disabled default is not reported")
        XCTAssertNotNil(SystemShortcuts.owner(keyCode: 20, modifiers: [.command, .shift], in: shortcuts), "Untouched defaults stay")
        let moved = SystemShortcuts.owner(keyCode: 126, modifiers: [.control, .option], in: shortcuts)
        XCTAssertEqual(moved?.name, "Mission Control")
        XCTAssertNil(SystemShortcuts.owner(keyCode: 126, modifiers: .control, in: shortcuts), "A rebound default leaves its old key")
        XCTAssertEqual(SystemShortcuts.owner(keyCode: 123, modifiers: [.control, .shift], in: shortcuts)?.name, "Move left a space",
            "The fn flag on arrow keys is ignored")
    }

    func testConflictsNameTheOwnerAndSuggestFreeKeys() {
        let system = SystemShortcuts.enabled(overrides: nil)
        let messages = shortcutConflictMessages(
            assignments: ["spotlight": "cmd-space", "a": "alt-k", "b": "alt-k", "free": "alt-j"],
            titles: ["spotlight": "Open palette", "a": "Focus left", "b": "Focus right", "free": "Free"],
            customNotations: ["ctrl-alt-k"], system: system)
        XCTAssertTrue(messages["spotlight"]?.hasPrefix("macOS uses this for Show Spotlight search. Try ") == true)
        XCTAssertEqual(messages["a"]?.contains("Also assigned to Focus right"), true)
        XCTAssertNil(messages["free"])
        let suggestions = freeShortcutAlternatives(keyCode: 40, taken: [ShortcutKey(keyCode: 40, modifiers: .option),
            ShortcutKey(keyCode: 40, modifiers: [.control, .option])], system: system)
        XCTAssertEqual(suggestions, [[.option, .shift], [.command, .option]], "Taken modifiers are skipped")
    }
}
