import Foundation
import XCTest
@testable import NativeSpaces

final class NativeSpacesReconciliationTests: XCTestCase {
    private func topology(a: String = "1", b: String = "3") -> [NativeSpaceDisplay] {
        [NativeSpaceDisplay(identifier: "a", activeSpaceID: a, spaces: [
            NativeSpace(id: "1", uuid: "one", type: 0), NativeSpace(id: "2", uuid: "two", type: 0),
        ]), NativeSpaceDisplay(identifier: "b", activeSpaceID: b, spaces: [
            NativeSpace(id: "3", uuid: "three", type: 0), NativeSpace(id: "4", uuid: "four", type: 4),
        ])]
    }

    func testOnlyIncomingSpaceIsTargetedForOrdinarySwitch() {
        XCTAssertEqual(NativeSpacesReconciliation.targets(previous: topology(), current: topology(a: "2")), ["2"])
        XCTAssertEqual(NativeSpacesReconciliation.targets(previous: topology(), current: topology(a: "2", b: "4")), ["2", "4"])
    }

    func testInitialWindowEventAndStructuralChangeRefreshCurrentSpaces() {
        XCTAssertEqual(NativeSpacesReconciliation.targets(previous: nil, current: topology()), ["1", "3"])
        XCTAssertEqual(NativeSpacesReconciliation.targets(previous: topology(), current: topology()), ["1", "3"])
        XCTAssertEqual(NativeSpacesReconciliation.targets(previous: Array(topology().prefix(1)), current: topology()), ["1", "3"])
    }
}
