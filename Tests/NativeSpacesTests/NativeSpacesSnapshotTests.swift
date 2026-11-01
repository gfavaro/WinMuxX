import Foundation
import XCTest
@testable import NativeSpaces

final class NativeSpacesSnapshotTests: XCTestCase {
    private func space(_ id: UInt64, _ type: Int = 0) -> [String: Any] {
        ["id64": NSNumber(value: id), "ManagedSpaceID": NSNumber(value: id), "uuid": "space-\(id)", "type": type]
    }
    private func display(_ name: String, _ active: UInt64, _ spaces: [[String: Any]]) -> [String: Any] {
        ["Display Identifier": name, "Current Space": space(active), "Spaces": spaces]
    }

    func testPerDisplayActivationAndFullscreenRetainIndependentIdentity() throws {
        let parsed = try NativeSpacesSnapshot.parseDisplays([
            display("external", 3, [space(1), space(3, 4)]),
            display("built-in", 2, [space(2)]),
        ])
        XCTAssertEqual(parsed.map(\.activeSpaceID), ["3", "2"])
        XCTAssertFalse(parsed[0].spaces[1].isDesktop)
        XCTAssertTrue(parsed[1].spaces[0].isDesktop)
        let reordered = try NativeSpacesSnapshot.parseDisplays([display("external", 1, [space(3, 4), space(1)])])
        XCTAssertEqual(reordered[0].spaces.map(\.id), ["3", "1"])
    }

    func testMissingActiveOrPartialTopologyIsRejectedInsteadOfInventingDesktop() {
        for raw in [[], [display("one", 2, [space(1)])], [display("one", 1, [space(1)]), display("one", 1, [space(1)])], [display("one", 1, [])]] as [[[String: Any]]] {
            XCTAssertThrowsError(try NativeSpacesSnapshot.parseDisplays(raw))
        }
    }

    func testUnknownFutureSpaceTypesArePreservedAndNotManaged() throws {
        let parsed = try NativeSpacesSnapshot.parseDisplays([display("Main", 7, [space(7, 99)])])
        XCTAssertFalse(parsed[0].spaces[0].isDesktop)
        XCTAssertEqual(parsed[0].identifier, "Main")
    }

    func test64BitIdentifiersSurviveJSONWithoutFloatingPointConversion() throws {
        let id = UInt64.max - 1
        let parsed = try NativeSpacesSnapshot.parseDisplays([display("one", id, [space(id)])])
        let encoded = try JSONEncoder().encode(parsed)
        XCTAssertEqual(try JSONDecoder().decode([NativeSpaceDisplay].self, from: encoded)[0].activeSpaceID, String(id))
    }

    func testInvalidAndConflictingIdentityValuesAreRejected() {
        for value: Any in [NSNumber(value: true), NSNumber(value: -1), NSNumber(value: 1.5), NSNumber(value: 0)] {
            let bad: [String: Any] = ["id64": value, "type": 0]
            XCTAssertThrowsError(try NativeSpacesSnapshot.parseDisplays([display("one", 1, [bad])]))
        }
        var conflicting = space(1)
        conflicting["ManagedSpaceID"] = NSNumber(value: 2)
        XCTAssertThrowsError(try NativeSpacesSnapshot.parseDisplays([display("one", 1, [conflicting])]))
    }

    func testSharedAndUnknownWindowMembershipAreNotAssignedArbitrarily() {
        XCTAssertNil(NativeWindowMembership(windowID: 1, spaceIDs: nil).unambiguousSpaceID)
        XCTAssertNil(NativeWindowMembership(windowID: 1, spaceIDs: []).unambiguousSpaceID)
        XCTAssertNil(NativeWindowMembership(windowID: 1, spaceIDs: ["2", "3"]).unambiguousSpaceID)
        XCTAssertEqual(NativeWindowMembership(windowID: 1, spaceIDs: ["2"]).unambiguousSpaceID, "2")
    }
}
