@testable import AppBundle
import AppKit
import Common
import XCTest

final class RefreshFocusSyncTest: XCTestCase {
    func testActivationRaisesSelectedWindowAfterWorkspaceSwitch() {
        XCTAssertTrue(shouldRaiseActivatedWindow(
            event: .globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue),
            previousWorkspace: "1", currentWorkspace: "2", nativeWindowId: 42, logicalWindowId: 42
        ))
    }

    func testActivationDoesNotRaiseIfWorkspaceOrSelectedWindowDidNotMatch() {
        let activation = RefreshSessionEvent.globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue)
        XCTAssertFalse(shouldRaiseActivatedWindow(event: activation, previousWorkspace: "1", currentWorkspace: "1", nativeWindowId: 42, logicalWindowId: 42))
        XCTAssertFalse(shouldRaiseActivatedWindow(event: activation, previousWorkspace: "1", currentWorkspace: "2", nativeWindowId: 42, logicalWindowId: 43))
        XCTAssertFalse(shouldRaiseActivatedWindow(event: activation, previousWorkspace: "1", currentWorkspace: "2", nativeWindowId: nil, logicalWindowId: nil))
        XCTAssertFalse(shouldRaiseActivatedWindow(event: .hotkeyBinding, previousWorkspace: "1", currentWorkspace: "2", nativeWindowId: 42, logicalWindowId: 42))
    }

    @MainActor
    func testShouldNotSyncFocusBackToPopupWindow() {
        setUpWorkspacesForTests()

        let popup = TestWindow.new(id: 1, parent: macosPopupWindowsContainer)

        XCTAssertFalse(shouldSyncFocusBackToMacOs(nativeFocused: popup, frontmostActivationPolicy: .accessory))
    }

    @MainActor
    func testShouldNotSyncFocusBackToAccessoryAppWithoutFocusedWindow() {
        XCTAssertFalse(shouldSyncFocusBackToMacOs(nativeFocused: nil, frontmostActivationPolicy: .accessory))
    }

    @MainActor
    func testShouldSyncFocusBackToRegularWorkspaceWindow() {
        setUpWorkspacesForTests()

        let window = TestWindow.new(id: 1, parent: focus.workspace)

        XCTAssertTrue(shouldSyncFocusBackToMacOs(nativeFocused: window, frontmostActivationPolicy: .regular))
    }
}
