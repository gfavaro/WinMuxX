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

    /// Opening System Settings from another workspace took the user to workspace 3; a floating
    /// window now comes to the workspace it was activated from instead.
    func testActivatedFloatingWindowFromAHiddenWorkspaceComesHere() {
        setUpWorkspacesForTests()
        let here = focus.workspace
        _ = TestWindow.new(id: 1, parent: here.rootTilingContainer).focusWindow()
        let hidden = Workspace.get(byName: "other")
        let floating = TestWindow.new(id: 2, parent: hidden)
        let tiled = TestWindow.new(id: 3, parent: hidden.rootTilingContainer)
        XCTAssertFalse(hidden.isVisible)
        let selection = runtime.refresh.workspaceSelectionGeneration
        let fromHere = RefreshActivationContext(generation: 1, workspaceName: here.name, pid: floating.app.pid,
                                                selectionGeneration: selection)

        XCTAssertTrue(shouldBringActivatedWindowHere(floating, activation: fromHere))
        XCTAssertFalse(shouldBringActivatedWindowHere(floating,
            activation: RefreshActivationContext(generation: 1, workspaceName: here.name, pid: floating.app.pid,
                                                 selectionGeneration: selection &- 1)),
            "The user left and returned since the activation; it is not from this visit")
        XCTAssertFalse(shouldBringActivatedWindowHere(tiled, activation: fromHere), "Tiled windows keep their layout")
        XCTAssertFalse(shouldBringActivatedWindowHere(floating, activation: nil), "No activation, as when focus lags a workspace switch")
        XCTAssertFalse(shouldBringActivatedWindowHere(floating,
            activation: RefreshActivationContext(generation: 1, workspaceName: hidden.name, pid: floating.app.pid,
                                                 selectionGeneration: selection)),
            "Activated from another workspace than the current one")
        XCTAssertFalse(shouldBringActivatedWindowHere(floating,
            activation: RefreshActivationContext(generation: 1, workspaceName: here.name, pid: floating.app.pid + 1,
                                                 selectionGeneration: selection)),
            "Another app was activated")
        config.followAppActivation.excludeApps = [floating.app.rawAppBundleId ?? ""]
        XCTAssertFalse(shouldBringActivatedWindowHere(floating, activation: fromHere), "Excluded apps are left alone")
    }

    func testReselectingTheCurrentWorkspaceKeepsAPendingActivationButLeavingDoesNot() throws {
        setUpWorkspacesForTests()
        let here = focus.workspace
        _ = TestWindow.new(id: 1, parent: here.rootTilingContainer).focusWindow()
        let floating = TestWindow.new(id: 2, parent: Workspace.get(byName: "other"))
        XCTAssertTrue(activateWorkspaceForUser(here, on: mainMonitor))
        recordRefreshActivation(workspaceName: here.name, pid: floating.app.pid)
        let activation = try XCTUnwrap(pendingRefreshActivationForTests())
        XCTAssertTrue(activateWorkspaceForUser(here, on: mainMonitor))
        XCTAssertTrue(shouldBringActivatedWindowHere(floating, activation: activation), "Reselecting is not leaving")
        XCTAssertTrue(activateWorkspaceForUser(Workspace.get(byName: "away"), on: mainMonitor))
        XCTAssertTrue(activateWorkspaceForUser(here, on: mainMonitor))
        XCTAssertFalse(shouldBringActivatedWindowHere(floating, activation: activation), "A new visit")
    }

    /// The rule allowed the move but a double-optional check skipped it; exercise the move itself.
    func testActivatingAFloatingWindowOnAHiddenWorkspaceMovesItHereAndFocusesIt() {
        setUpWorkspacesForTests()
        let here = focus.workspace
        _ = TestWindow.new(id: 1, parent: here.rootTilingContainer).focusWindow()
        let floating = TestWindow.new(id: 2, parent: Workspace.get(byName: "other"))
        recordRefreshActivation(workspaceName: here.name, pid: floating.app.pid)
        updateFocusCache(floating)
        XCTAssertTrue(floating.nodeWorkspace === here)
        XCTAssertTrue(floating.isFloating)
        XCTAssertEqual(focus.windowOrNil?.windowId, floating.windowId)
        XCTAssertTrue(focus.workspace === here, "The user stays on their workspace")
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
