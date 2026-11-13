@testable import AppBundle
import Foundation
import XCTest

final class AXNotificationOwnerTest: XCTestCase {
    func testNotificationFromCurrentAppOwnerIsAccepted() {
        let registeredApp = NSObject()
        XCTAssertTrue(isSameAXNotificationOwner(emittingApp: registeredApp, managedApp: registeredApp))
    }

    func testNotificationFromPreviousAppOwnerIsRejected() {
        let previousApp = NSObject()
        let replacementApp = NSObject()
        XCTAssertFalse(isSameAXNotificationOwner(emittingApp: previousApp, managedApp: replacementApp),
                       "PID or WindowServer ID reuse must not make a stale AX callback authoritative")
    }

    func testUnknownOwnerCannotAuthorizeMutation() {
        let app = NSObject()
        XCTAssertFalse(isSameAXNotificationOwner(emittingApp: nil, managedApp: app))
        XCTAssertFalse(isSameAXNotificationOwner(emittingApp: app, managedApp: nil))
        XCTAssertFalse(isSameAXNotificationOwner(emittingApp: nil, managedApp: nil))
    }
    func testDestroyedEntryRequiresCurrentOwnerOrConfirmedNativeClosure() {
        let current = NSObject()
        let previous = NSObject()
        XCTAssertTrue(shouldRetireAXWindowEntry(emittingApp: current, managedApp: current,
                                                windowStillExists: true))
        XCTAssertFalse(shouldRetireAXWindowEntry(emittingApp: previous, managedApp: current,
                                                 windowStillExists: true))
        XCTAssertFalse(shouldRetireAXWindowEntry(emittingApp: current, managedApp: nil,
                                                 windowStillExists: true),
                       "A live but untracked ID might have been reused by a new window")
        XCTAssertTrue(shouldRetireAXWindowEntry(emittingApp: current, managedApp: nil,
                                                windowStillExists: false))
        XCTAssertFalse(shouldRetireAXWindowEntry(emittingApp: nil, managedApp: nil,
                                                 windowStillExists: false))
    }
}
