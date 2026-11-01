@testable import AppBundle
import AppKit
import XCTest

final class RunningProcessIdentityTest: XCTestCase {
    /// A window's app was destroyed while running because its `frontmostApplication` object was
    /// not the same object as the observed list's, leaving its windows unable to move or park.
    func testObjectsForOneProcessAreTheSameProcess() throws {
        let running = NSWorkspace.shared.runningApplications
        guard let listed = running.first(where: { $0.bundleIdentifier == "com.apple.finder" }) ?? running.first(where: { $0.bundleIdentifier != nil }),
              let lookedUp = NSRunningApplication(processIdentifier: listed.processIdentifier)
        else { throw XCTSkip("No LaunchServices application to look up") }
        // AppKit currently returns a distinct object here, which is the case that broke; either is legal.
        XCTAssertTrue(isSameRunningProcess(listed, lookedUp))
        XCTAssertTrue(isSameRunningProcess(listed, listed))
    }

    func testOtherProcessIsNotTheSameProcess() throws {
        let apps = NSWorkspace.shared.runningApplications
        guard apps.count >= 2 else { throw XCTSkip("Needs two running applications") }
        XCTAssertFalse(isSameRunningProcess(apps[0], apps[1]))
    }

    func testRegistrationNeverEvictsALiveApp() {
        var asked = 0
        func incoming(_ terminated: Bool) -> () -> Bool { { asked += 1; return terminated } }

        XCTAssertEqual(appRegistrationDecision(existingTerminated: false, sameProcess: true, incomingTerminated: incoming(false)), .reuse)
        XCTAssertEqual(asked, 0, "The common case makes no LaunchServices request")
        // A request carrying an earlier, ended process must not evict the live one.
        XCTAssertEqual(appRegistrationDecision(existingTerminated: false, sameProcess: false, incomingTerminated: incoming(true)), .reject)
        XCTAssertEqual(appRegistrationDecision(existingTerminated: false, sameProcess: false, incomingTerminated: incoming(false)), .reuse)
        // Only an ended registration is replaced, and only by a running process.
        XCTAssertEqual(appRegistrationDecision(existingTerminated: true, sameProcess: false, incomingTerminated: incoming(false)), .replace)
        XCTAssertEqual(appRegistrationDecision(existingTerminated: true, sameProcess: false, incomingTerminated: incoming(true)), .reject)
    }
}
