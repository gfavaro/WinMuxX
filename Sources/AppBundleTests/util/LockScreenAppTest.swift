@testable import AppBundle
import AppKit
import XCTest

final class LockScreenAppTest: XCTestCase {
    func testLockScreenIsRecognisedByItsExecutableWithoutLaunchServices() throws {
        XCTAssertFalse(isLockScreenApp(NSRunningApplication.current))
        XCTAssertFalse(isLockScreenApp(nil))
        let loginwindow = try XCTUnwrap(NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == lockScreenAppBundleId })
        XCTAssertTrue(isLockScreenApp(loginwindow))
    }
}
