@testable import AppBundle
import AppKit
import XCTest

final class WindowClassificationTest: XCTestCase {
    private final class Element: AxUiElementMock {
        var attributes: [String: Any] = [:]
        func containingWindowId() -> CGWindowID? { 1 }
        func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? { attributes[attr.key] as? Attr.T }

        static func window(fullscreen: Bool?, close: Bool? = true) -> Element {
            let window = Element()
            window.attributes[kAXSubroleAttribute] = kAXStandardWindowSubrole
            for (key, enabled) in [(kAXFullScreenButtonAttribute, fullscreen), (kAXCloseButtonAttribute, close)] {
                if let enabled {
                    let button = Element()
                    button.attributes[kAXEnabledAttribute] = enabled
                    window.attributes[key] = button
                }
            }
            return window
        }
    }

    func testUtilityWindowsFloatWithMissingOrDisabledFullscreenControls() {
        for enabled: Bool? in [nil, false, true] {
            let window = Element.window(fullscreen: enabled)
            XCTAssertEqual(window.isDialogHeuristic(.finder, .normalWindow), enabled != true)
            XCTAssertEqual(window.isDialogHeuristic(nil, .normalWindow), enabled != true)
        }
    }

    func testTitlebarOptionalApplicationsRemainTiled() {
        for app: KnownBundleId in [.alacritty, .kitty, .wezterm, .iterm2, .emacs, .qutebrowser,
                                  .vscode, .vscodium, .chrome, .activityMonitor, .gimp, .steam] {
            for enabled: Bool? in [nil, false] {
                XCTAssertFalse(Element.window(fullscreen: enabled).isDialogHeuristic(app, .normalWindow), app.rawValue)
            }
        }
    }

    func testGhosttyHiddenTitlebarTilesButUtilityAndQuickTerminalDoNot() {
        XCTAssertFalse(Element.window(fullscreen: nil, close: nil).isDialogHeuristic(.ghostty, .normalWindow))
        XCTAssertTrue(Element.window(fullscreen: false).isDialogHeuristic(.ghostty, .normalWindow))
        let quickTerminal = Element.window(fullscreen: true)
        quickTerminal.attributes[kAXIdentifierAttribute] = "com.mitchellh.ghostty.quickTerminal"
        XCTAssertEqual(quickTerminal.getWindowType(axApp: Element(), .ghostty, .regular, .normalWindow), .popup)
    }

    func testNativeDialogsFloatEvenWithFullscreenControls() {
        let dialog = Element.window(fullscreen: true)
        dialog.attributes[kAXSubroleAttribute] = kAXDialogSubrole
        XCTAssertEqual(dialog.getWindowType(axApp: Element(), nil, .regular, .normalWindow), .dialog)
    }
}
