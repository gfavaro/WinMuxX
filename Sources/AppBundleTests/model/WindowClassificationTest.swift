@testable import AppBundle
import AppKit
import Common
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

    func testAccessoryBundleDeclarationAcceptsSupportedPlistTypes() {
        for value: Any in [true, NSNumber(value: 1), NSNumber(value: 2), "1", "true", " TRUE "] {
            XCTAssertTrue(appDeclaresAccessory(["LSUIElement": value]), "\(value)")
        }
        for value: Any in [false, NSNumber(value: 0), "0", "false", "yes", "", NSNull(), ["invalid"]] {
            XCTAssertFalse(appDeclaresAccessory(["LSUIElement": value]), "\(value)")
        }
        XCTAssertFalse(appDeclaresAccessory(nil))
        XCTAssertFalse(appDeclaresAccessory([:]))
    }

    func testAccessoryRealWindowsFloatRegardlessOfCurrentActivationPolicy() {
        let window = Element.window(fullscreen: true)
        for policy: NSApplication.ActivationPolicy in [.regular, .accessory] {
            XCTAssertEqual(window.getWindowType(axApp: Element(), nil, policy, .normalWindow, accessory: true), .dialog)
            XCTAssertEqual(window.getWindowType(axApp: Element(), nil, policy, .normalWindow, accessory: false), .window)
        }
    }

    func testAccessoryClassificationDoesNotPromotePopupsToFloatingWindows() {
        let window = Element.window(fullscreen: true, close: nil)
        XCTAssertEqual(window.getWindowType(axApp: Element(), nil, .accessory, .normalWindow, accessory: true), .popup)
        XCTAssertEqual(window.getWindowType(axApp: Element(), nil, .regular, .normalWindow, accessory: true), .dialog)
        let quickTerminal = Element.window(fullscreen: true)
        quickTerminal.attributes[kAXIdentifierAttribute] = "com.mitchellh.ghostty.quickTerminal"
        XCTAssertEqual(quickTerminal.getWindowType(axApp: Element(), .ghostty, .regular, .normalWindow, accessory: true), .popup)
    }

    @MainActor
    func testAccessoryDefaultBindingCanBeOverriddenByWindowRule() async throws {
        setUpWorkspacesForTests()
        let savedConfig = config
        let savedEnabled = TrayMenuModel.shared.isEnabled
        defer { setUpWorkspacesForTests(); config = savedConfig; TrayMenuModel.shared.isEnabled = savedEnabled }
        let (parsed, errors) = parseConfig("""
        config-version = 2
        [[on-window-detected]]
        if.app-id = 'bobko.WinMux.test-app'
        run = 'layout tiling'
        """)
        XCTAssertTrue(errors.isEmpty)
        config.onWindowDetected = parsed.onWindowDetected
        TrayMenuModel.shared.isEnabled = true
        let workspace = focus.workspace
        let type = Element.window(fullscreen: true).getWindowType(axApp: Element(), nil, .regular, .normalWindow, accessory: true)
        let binding = bindingDataForNewWindow(type: type, workspace: workspace, window: nil)
        let window = TestWindow.new(id: 501, parent: binding.parent)
        XCTAssertTrue(window.isFloating)
        try await tryOnWindowDetected(window)
        XCTAssertFalse(window.isFloating)
        XCTAssertTrue(window.nodeWorkspace === workspace)
    }

    @MainActor
    func testRestoredTilingOverridesAccessoryInitialFloatingBinding() async throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        let workspace = focus.workspace
        let original = TestWindow.new(id: 502, parent: workspace.rootTilingContainer)
        let snapshot = FrozenWorld(workspaces: [FrozenWorkspace(workspace)], monitors: monitors.map(FrozenMonitor.init), windowIds: [502])
        original.unbindFromParent()
        let type = Element.window(fullscreen: true).getWindowType(axApp: Element(), nil, .accessory, .normalWindow, accessory: true)
        let binding = bindingDataForNewWindow(type: type, workspace: workspace, window: nil)
        let replacement = TestWindow.new(id: 502, parent: binding.parent)
        XCTAssertTrue(replacement.isFloating)
        let restored = try await restoreFrozenWorldIfNeeded(snapshot, newlyDetectedWindow: replacement)
        XCTAssertTrue(restored)
        XCTAssertFalse(replacement.isFloating)
        XCTAssertTrue(replacement.nodeWorkspace === workspace)
    }

    func testUtilityWindowsFloatWithMissingOrDisabledFullscreenControls() {
        for enabled: Bool? in [nil, false, true] {
            let window = Element.window(fullscreen: enabled)
            XCTAssertEqual(window.isDialogHeuristic(.finder, .normalWindow, accessory: false), enabled != true)
            XCTAssertEqual(window.isDialogHeuristic(nil, .normalWindow, accessory: false), enabled != true)
        }
    }

    func testTitlebarOptionalApplicationsRemainTiled() {
        for app: KnownBundleId in [.alacritty, .kitty, .wezterm, .iterm2, .emacs, .qutebrowser,
                                  .vscode, .vscodium, .chrome, .activityMonitor, .gimp, .steam] {
            for enabled: Bool? in [nil, false] {
                XCTAssertFalse(Element.window(fullscreen: enabled).isDialogHeuristic(app, .normalWindow, accessory: false), app.rawValue)
            }
        }
    }

    func testGhosttyHiddenTitlebarTilesButUtilityAndQuickTerminalDoNot() {
        XCTAssertFalse(Element.window(fullscreen: nil, close: nil).isDialogHeuristic(.ghostty, .normalWindow, accessory: false))
        XCTAssertTrue(Element.window(fullscreen: false).isDialogHeuristic(.ghostty, .normalWindow, accessory: false))
        let quickTerminal = Element.window(fullscreen: true)
        quickTerminal.attributes[kAXIdentifierAttribute] = "com.mitchellh.ghostty.quickTerminal"
        XCTAssertEqual(quickTerminal.getWindowType(axApp: Element(), .ghostty, .regular, .normalWindow, accessory: false), .popup)
    }

    func testNativeDialogsFloatEvenWithFullscreenControls() {
        let dialog = Element.window(fullscreen: true)
        dialog.attributes[kAXSubroleAttribute] = kAXDialogSubrole
        XCTAssertEqual(dialog.getWindowType(axApp: Element(), nil, .regular, .normalWindow, accessory: false), .dialog)
    }
}
