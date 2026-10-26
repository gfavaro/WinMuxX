import Foundation
import XCTest
@testable import NativeSpaces

final class NativeSpaceEligibilityTests: XCTestCase {
    private let a = NativeSpace(id: "1", uuid: "a", type: 0)
    private let b = NativeSpace(id: "2", uuid: "b", type: 0)
    private let full = NativeSpace(id: "3", uuid: "full", type: 4)

    private func snapshot(_ membership: [String]?, sharedDesktop: Bool = false) -> NativeSpacesSnapshot {
        NativeSpacesSnapshot(displays: [
            NativeSpaceDisplay(identifier: "external", activeSpaceID: "1", spaces: [a, b, full]),
            NativeSpaceDisplay(identifier: "built-in", activeSpaceID: sharedDesktop ? "1" : "4", spaces: sharedDesktop ? [a] : [NativeSpace(id: "4", uuid: "d", type: 0)]),
        ], windows: [NativeWindowMembership(windowID: 10, spaceIDs: membership)], readMilliseconds: 0, capturedAt: .distantPast)
    }

    func testOnlyCorrectActiveDesktopIsEligible() {
        let state = snapshot(["1"])
        XCTAssertEqual(state.eligibility(windowID: 10, on: "external"), .desktop(spaceID: "1", spaceUUID: "a"))
        XCTAssertEqual(state.eligibility(windowID: 10, on: "built-in"), .excluded(.otherDisplay))
        XCTAssertEqual(state.eligibility(windowID: 10, on: "disconnected"), .excluded(.unknownDisplay))
    }

    func testInactiveAndNativeFullscreenSpacesAreExcluded() {
        XCTAssertEqual(snapshot(["2"]).eligibility(windowID: 10, on: "external"), .excluded(.inactiveSpace))
        XCTAssertEqual(snapshot(["3"]).eligibility(windowID: 10, on: "external"), .excluded(.nonDesktopSpace))
    }

    func testMissingMembershipCannotBorrowActiveWorkspace() {
        for ids: [String]? in [nil, []] {
            XCTAssertEqual(snapshot(ids).eligibility(windowID: 10, on: "external"), .excluded(.unknownMembership))
        }
        XCTAssertEqual(snapshot(["99"]).eligibility(windowID: 10, on: "external"), .excluded(.unknownSpace))
        XCTAssertEqual(snapshot(["1"]).eligibility(windowID: 11, on: "external"), .excluded(.unknownWindow))
    }

    func testAllSpacesWindowsAndSharedDesktopsAreNotDuplicated() {
        XCTAssertEqual(snapshot(["1", "2"]).eligibility(windowID: 10, on: "external"), .excluded(.sharedWindow))
        XCTAssertEqual(snapshot(["1"], sharedDesktop: true).eligibility(windowID: 10, on: "external"), .excluded(.sharedDesktop))
    }
}
