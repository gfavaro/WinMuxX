import AppKit
import Common
import XCTest

/// Only wake and startup force AX parking writes even when native geometry agrees.
/// Other events still verify native geometry before trusting a remembered parking flag.
final class RefreshSessionEventReassertionTest: XCTestCase {
    func testOnlyWakeAndStartupRequireHiddenWindowsReassertion() {
        XCTAssertTrue(RefreshSessionEvent.startup.requiresHiddenWindowsReassertion)
        XCTAssertTrue(
            RefreshSessionEvent.globalObserver(NSWorkspace.didWakeNotification.rawValue)
                .requiresHiddenWindowsReassertion
        )
        XCTAssertTrue(
            RefreshSessionEvent.globalObserver(NSWorkspace.screensDidWakeNotification.rawValue)
                .requiresHiddenWindowsReassertion
        )

        XCTAssertFalse(RefreshSessionEvent.ax(kAXMovedNotification as String).requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.ax(kAXResizedNotification as String).requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.ax(kAXWindowCreatedNotification as String).requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.ax(kAXUIElementDestroyedNotification as String).requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.globalObserverLeftMouseUp.requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.resetManipulatedWithMouse.requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.hotkeyBinding.requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.configAutoReload.requiresHiddenWindowsReassertion)
        XCTAssertFalse(
            RefreshSessionEvent.globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue)
                .requiresHiddenWindowsReassertion
        )
    }
}
