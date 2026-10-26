import Foundation
import XCTest
@testable import NativeSpaces

private final class AuthorityHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: NativeSpaceWriteAuthority?
    var value: NativeSpaceWriteAuthority? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class NativeSpaceWriteAuthorityTests: XCTestCase {
    private let launched = Date(timeIntervalSince1970: 100)
    private var identity: NativeWindowWriteIdentity {
        NativeWindowWriteIdentity(windowID: 10, pid: 42, processLaunchDate: launched,
            displayIdentifier: "display", spaceID: "1", spaceUUID: "desktop")
    }
    private func snapshot(active: String = "1", memberships: [String]? = ["1"], type: Int = 0) -> NativeSpacesSnapshot {
        NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display", activeSpaceID: active,
            spaces: [NativeSpace(id: "1", uuid: "desktop", type: type), NativeSpace(id: "2", uuid: "other", type: 0)])],
            windows: [NativeWindowMembership(windowID: 10, spaceIDs: memberships)], readMilliseconds: 0, capturedAt: .now)
    }
    private func permit(_ gate: NativeSpaceWriteAuthority) -> NativeSpaceWritePermit? {
        gate.permit(windowID: 10, pid: 42, processLaunchDate: launched)
    }

    func testOnlyActiveUnambiguousDesktopIdentityReceivesPermit() throws {
        let gate = NativeSpaceWriteAuthority { _ in true }
        XCTAssertNil(permit(gate))
        for invalid in [snapshot(active: "2"), snapshot(memberships: nil), snapshot(memberships: []),
                        snapshot(memberships: ["1", "2"]), snapshot(type: 4)] {
            gate.replace(snapshot: invalid, identities: [identity])
            XCTAssertNil(permit(gate))
        }
        gate.replace(snapshot: snapshot(), identities: [identity])
        try XCTUnwrap(permit(gate)).check()
        XCTAssertNil(gate.permit(windowID: 10, pid: 99, processLaunchDate: launched))
        XCTAssertNil(gate.permit(windowID: 10, pid: 42, processLaunchDate: launched.addingTimeInterval(1)))
    }

    func testInvalidationAndReplacementRevokePreviouslyQueuedWork() throws {
        let gate = NativeSpaceWriteAuthority { _ in true }
        gate.replace(snapshot: snapshot(), identities: [identity])
        let first = try XCTUnwrap(permit(gate))
        gate.invalidate()
        XCTAssertThrowsError(try first.check()) { XCTAssertEqual($0 as? NativeSpaceWriteError, .revoked) }
        gate.replace(snapshot: snapshot(), identities: [identity])
        let next = try XCTUnwrap(permit(gate))
        XCTAssertThrowsError(try first.check())
        try next.check()
    }

    func testLiveOwnershipChangeRejectsOtherwiseCurrentPermit() throws {
        let gate = NativeSpaceWriteAuthority { _ in false }
        gate.replace(snapshot: snapshot(), identities: [identity])
        let current = try XCTUnwrap(permit(gate))
        XCTAssertThrowsError(try current.check()) { XCTAssertEqual($0 as? NativeSpaceWriteError, .liveOwnershipChanged) }
    }

    func testInvalidationWhileLiveQueryRunsCannotAuthorizeWrite() throws {
        let holder = AuthorityHolder()
        let gate = NativeSpaceWriteAuthority { _ in holder.value?.invalidate(); return true }
        holder.value = gate
        defer { holder.value = nil }
        gate.replace(snapshot: snapshot(), identities: [identity])
        let current = try XCTUnwrap(permit(gate))
        XCTAssertThrowsError(try current.check()) { XCTAssertEqual($0 as? NativeSpaceWriteError, .revoked) }
    }

    func testDuplicateWindowIdentityDoesNotPickAnArbitraryOwner() {
        let gate = NativeSpaceWriteAuthority { _ in true }
        gate.replace(snapshot: snapshot(), identities: [identity, identity])
        XCTAssertNil(permit(gate))
    }
}
