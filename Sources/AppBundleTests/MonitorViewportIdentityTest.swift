@testable import AppBundle
import XCTest

final class MonitorViewportIdentityTest: XCTestCase {
    func testMatchingDisplayIdentityAllowsViewportReuse() {
        XCTAssertTrue(canReuseMonitorViewport(recordedDisplayUUID: "display-A",
                                              targetDisplayUUID: "display-A"))
    }

    func testConflictingKnownDisplayIdentityRejectsViewportReuse() {
        XCTAssertFalse(canReuseMonitorViewport(recordedDisplayUUID: "display-A",
                                               targetDisplayUUID: "display-B"))
    }

    func testUnknownDisplayIdentityPreservesCoordinateFallback() {
        XCTAssertTrue(canReuseMonitorViewport(recordedDisplayUUID: nil,
                                              targetDisplayUUID: "display-B"))
        XCTAssertTrue(canReuseMonitorViewport(recordedDisplayUUID: "display-A",
                                              targetDisplayUUID: nil))
        XCTAssertTrue(canReuseMonitorViewport(recordedDisplayUUID: nil,
                                              targetDisplayUUID: nil))
    }
}
