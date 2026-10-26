import Foundation
import XCTest
@testable import NativeSpaces

final class NativeSpacesWindowEventTests: XCTestCase {
    func testSpaceChangeAllowsEmptyPayloadButCreateDestroyRequireSpaceIdentity() {
        XCTAssertNotNil(Data().withUnsafeBytes { NativeSpacesWindowEvent.decode(kind: 1401, bytes: $0) })
        for kind: UInt32 in [1327, 1328] {
            XCTAssertNil(Data(repeating: 0, count: 7).withUnsafeBytes { NativeSpacesWindowEvent.decode(kind: kind, bytes: $0) })
            XCTAssertNil(Data(repeating: 0, count: 8).withUnsafeBytes { NativeSpacesWindowEvent.decode(kind: kind, bytes: $0) })
            var id: UInt64 = 4
            let event = withUnsafeBytes(of: &id) { NativeSpacesWindowEvent.decode(kind: kind, bytes: $0) }
            XCTAssertTrue(event?.changesTopology == true)
            XCTAssertNil(event?.windowID)
        }
    }

    func testWindowDepartureIsNotDecodedAsClosureOrSpaceIDAsWindowID() {
        var space: UInt64 = 42, window: UInt32 = 109245
        var data = withUnsafeBytes(of: &space) { Data($0) }
        data.append(withUnsafeBytes(of: &window) { Data($0) })
        let event = data.withUnsafeBytes { NativeSpacesWindowEvent.decode(kind: 1326, bytes: $0) }
        XCTAssertEqual(event?.windowID, window)
        XCTAssertFalse(event?.changesTopology == true)
        XCTAssertFalse(event?.confirmsClosure == true)
        XCTAssertEqual(event?.kind, 1326)
        XCTAssertNil(data.prefix(11).withUnsafeBytes { NativeSpacesWindowEvent.decode(kind: 1326, bytes: $0) })
    }

    func testMalformedAndUnknownWindowEventsAreRejected() {
        XCTAssertNil(Data([1, 2, 3]).withUnsafeBytes { NativeSpacesWindowEvent.decode(kind: 804, bytes: $0) })
        XCTAssertNil(Data(repeating: 0, count: 4).withUnsafeBytes { NativeSpacesWindowEvent.decode(kind: 804, bytes: $0) })
        XCTAssertNil(Data(repeating: 1, count: 12).withUnsafeBytes { NativeSpacesWindowEvent.decode(kind: 999, bytes: $0) })
    }

    func testOnlyExplicitWindowCloseConfirmsClosure() {
        var id: UInt32 = 123
        let event = withUnsafeBytes(of: &id) { NativeSpacesWindowEvent.decode(kind: 804, bytes: $0) }
        XCTAssertTrue(event?.confirmsClosure == true)
        XCTAssertEqual(event?.windowID, id)
        let hidden = withUnsafeBytes(of: &id) { NativeSpacesWindowEvent.decode(kind: 815, bytes: $0) }
        XCTAssertFalse(hidden?.confirmsClosure == true)
    }
}
