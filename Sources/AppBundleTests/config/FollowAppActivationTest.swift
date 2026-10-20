@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class FollowAppActivationTest: XCTestCase {
    override func tearDown() async throws { setUpWorkspacesForTests() }

    func testBooleanAndTableConfiguration() {
        for enabled in [true, false] {
            let parsed = parseConfig("config-version = 2\nfollow-app-activation = \(enabled)")
            XCTAssertTrue(parsed.errors.isEmpty)
            XCTAssertEqual(parsed.config.followAppActivation.follows("test.app"), enabled)
        }
        let parsed = parseConfig("""
        config-version = 2
        [follow-app-activation]
        enabled = true
        exclude-apps = ['com.apple.Safari']
        """)
        XCTAssertTrue(parsed.errors.isEmpty)
        XCTAssertFalse(parsed.config.followAppActivation.follows("com.apple.Safari"))
        XCTAssertTrue(parsed.config.followAppActivation.follows("test.editor"))
        XCTAssertTrue(parsed.config.followAppActivation.follows(nil))
        XCTAssertFalse(parseConfig("follow-app-activation = 'false'").errors.isEmpty)
        XCTAssertFalse(parseConfig("[follow-app-activation]\nexclude-apps = [4]").errors.isEmpty)
    }

    func testDisabledFollowingPreservesSameWorkspaceFocusAndExplicitCommands() {
        setUpWorkspacesForTests()
        config.followAppActivation.enabled = false
        let workspace = focus.workspace
        let local = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        _ = local.focusWindow()
        let other = TestWindow.new(id: 2, parent: Workspace.get(byName: "other").rootTilingContainer)
        XCTAssertFalse(ignoresCrossWorkspaceActivation(local))
        XCTAssertTrue(ignoresCrossWorkspaceActivation(other))
        for event in [RefreshSessionEvent.socketServer(parseCommand("focus right").cmdOrDie.args), .hotkeyBinding, .menuBarButton,
                      .globalObserver("workspaceSwipe"), .globalObserver("workspaceOverviewSelection")] {
            $refreshSessionEvent.withValue(event) {
                XCTAssertTrue(shouldSyncFocusBackToMacOs(nativeFocused: other, frontmostActivationPolicy: .regular))
            }
        }
        $refreshSessionEvent.withValue(.globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue)) {
            XCTAssertFalse(shouldSyncFocusBackToMacOs(nativeFocused: other, frontmostActivationPolicy: .regular))
            XCTAssertTrue(shouldSyncFocusBackToMacOs(nativeFocused: local, frontmostActivationPolicy: .regular))
        }
    }

    func testBrowserVideoSurfacesDoNotBecomeDocumentFocusTargets() {
        for browser in [KnownBundleId.safari, .helium, .chrome, .mozillaFirefox, .edge, .arc] {
            XCTAssertTrue(isBrowserFocusOverlay(app: browser, level: .alwaysOnTopWindow))
            XCTAssertTrue(isBrowserFocusOverlay(app: browser, level: .unknown(windowLevel: 25)))
            XCTAssertFalse(isBrowserFocusOverlay(app: browser, level: .normalWindow))
            XCTAssertFalse(isBrowserFocusOverlay(app: browser, level: nil))
        }
        XCTAssertFalse(isBrowserFocusOverlay(app: nil, level: .alwaysOnTopWindow))
        XCTAssertFalse(isBrowserFocusOverlay(app: .safari, level: .unknown(windowLevel: -1)))
    }
}
