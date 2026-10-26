import Foundation
import XCTest
@testable import NativeSpaces

final class NativeSpacesReaderTests: XCTestCase {
    private final class FakeQuery: NativeSpacesQuerying {
        var topologyReads = 0
        let changeDuringRead: Bool
        init(changeDuringRead: Bool = false) { self.changeDuringRead = changeDuringRead }

        func copyDisplays() throws -> [[String: Any]] {
            topologyReads += 1
            let active = changeDuringRead && topologyReads > 1 ? 2 : 1
            func space(_ id: Int) -> [String: Any] { ["id64": id, "type": 0] }
            return [["Display Identifier": "display", "Current Space": space(active), "Spaces": [space(1), space(2)]]]
        }
        func spaces(for id: UInt32) -> [String]? {
            switch id {
            case 1: ["1"]
            case 2: []
            case 3: nil
            default: ["1", "2"]
            }
        }
    }

    func testMissingPrivateAPIFailsExplicitlyWithoutFallbackInventory() async {
        let reader = NativeSpacesReader(makeBridge: { throw NativeSpacesError.unavailable("injected missing symbol") })
        do {
            _ = try await reader.snapshot(windowIDs: [1])
            XCTFail("missing APIs must not produce an empty successful snapshot")
        } catch {
            XCTAssertEqual(error as? NativeSpacesError, .unavailable("injected missing symbol"))
        }
    }

    func testSpaceChangeDuringMembershipQueryRejectsWholeSnapshot() async {
        let reader = NativeSpacesReader(makeBridge: { FakeQuery(changeDuringRead: true) })
        do {
            _ = try await reader.snapshot(windowIDs: [1])
            XCTFail("mixed generations must not authorize management")
        } catch {
            XCTAssertEqual(error as? NativeSpacesError, .invalidSnapshot("Space topology changed during read; retry after settling"))
        }
    }

    func testNilEmptyAndSharedMembershipStayDistinct() async throws {
        let reader = NativeSpacesReader(makeBridge: { FakeQuery() })
        let result = try await reader.snapshot(windowIDs: [4, 3, 2, 1, 1])
        XCTAssertEqual(result.windows.map(\.windowID), [1, 2, 3, 4])
        XCTAssertEqual(result.windows[0].unambiguousSpaceID, "1")
        XCTAssertEqual(result.windows[1].spaceIDs, [])
        XCTAssertNil(result.windows[2].spaceIDs)
        XCTAssertEqual(result.windows[3].spaceIDs, ["1", "2"])
    }

    func testInvalidAndUnboundedRequestIsRejected() async {
        let reader = NativeSpacesReader(makeBridge: { FakeQuery() })
        for ids in [[UInt32(0)], Array(repeating: UInt32(1), count: 1025)] {
            do {
                _ = try await reader.snapshot(windowIDs: ids)
                XCTFail("invalid request must fail")
            } catch {
                XCTAssertEqual(error as? NativeSpacesError, .invalidSnapshot("window IDs must be nonzero, at most 1024 per read"))
            }
        }
    }
}
