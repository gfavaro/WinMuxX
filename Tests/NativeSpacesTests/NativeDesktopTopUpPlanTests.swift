import XCTest
@testable import NativeSpaces

final class NativeDesktopTopUpPlanTests: XCTestCase {
    func testPlanningCountsOnlyDesktopsAndUsesAvailableHomeOrFirstDisplay() {
        let main = NativeSpaceDisplay(identifier: "main", activeSpaceID: "1", spaces: [
            NativeSpace(id: "1", uuid: "a", type: 0), NativeSpace(id: "9", uuid: "full", type: 4),
        ])
        let external = NativeSpaceDisplay(identifier: "external", activeSpaceID: "2", spaces: [
            NativeSpace(id: "2", uuid: "b", type: 0),
        ])
        XCTAssertEqual(NativeDesktopTopUpPlan.target(["1", "project", "4", "0"]), 4)
        let step = NativeDesktopTopUpPlan.next([main, external], target: 4, home: { _ in "external" })
        XCTAssertEqual(step?.number, 3)
        XCTAssertEqual(step?.display, "external")
        XCTAssertEqual(NativeDesktopTopUpPlan.next([main, external], target: 3, home: { _ in "missing" })?.display, "main")
        XCTAssertNil(NativeDesktopTopUpPlan.next([main, external], target: 2, home: { _ in "main" }))
        XCTAssertNil(NativeDesktopTopUpPlan.next([], target: 2, home: { _ in "main" }))
    }
}
