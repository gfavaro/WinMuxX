@testable import AppBundle
import AppKit
import XCTest

final class RunningProcessIdentityTest: XCTestCase {
    /// A window's app was destroyed while running because its `frontmostApplication` object was
    /// not the same object as the observed list's, leaving its windows unable to move or park.
    func testDifferentObjectsForOneProcessAreTheSameProcess() throws {
        let running = NSWorkspace.shared.runningApplications
        guard let listed = running.first(where: { $0.bundleIdentifier == "com.apple.finder" }) ?? running.first(where: { $0.bundleIdentifier != nil }),
              let lookedUp = NSRunningApplication(processIdentifier: listed.processIdentifier)
        else { throw XCTSkip("No LaunchServices application to look up") }
        XCTAssertFalse(listed === lookedUp, "AppKit hands out distinct objects; the fixture relies on it")
        XCTAssertTrue(isSameRunningProcess(listed, lookedUp))
        XCTAssertTrue(isSameRunningProcess(listed, listed))
    }

    func testOtherProcessIsNotTheSameProcess() throws {
        let apps = NSWorkspace.shared.runningApplications
        guard apps.count >= 2 else { throw XCTSkip("Needs two running applications") }
        XCTAssertFalse(isSameRunningProcess(apps[0], apps[1]))
    }
}
