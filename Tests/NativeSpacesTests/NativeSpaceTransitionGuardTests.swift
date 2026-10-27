import CoreGraphics
import XCTest
@testable import NativeSpaces

final class NativeSpaceTransitionGuardTests: XCTestCase {
    func testDisplaySizedMissionControlOverlayBlocksButOrdinaryWindowsDoNot() {
        func row(layer: Int = 19, width: Int = 1920, height: Int = 1080, pid: Int = 42) -> [String: Any] {
            [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
             kCGWindowBounds as String: ["X": 500, "Y": -500, "Width": width, "Height": height]]
        }
        let sizes = [CGSize(width: 1920, height: 1080), CGSize(width: 1440, height: 900)]
        let bundle: (pid_t) -> String? = { $0 == 42 ? "com.apple.WindowManager" : "fixture" }
        XCTAssertTrue(NativeSpaceTransitionGuard.isMissionControlVisible([row()], screenSizes: sizes, bundleIdentifierForPID: bundle))
        XCTAssertTrue(NativeSpaceTransitionGuard.isMissionControlVisible([row(width: 1440, height: 900)], screenSizes: sizes, bundleIdentifierForPID: bundle))
        for ordinary in [row(layer: 0), row(width: 300), row(pid: 43), [:]] {
            XCTAssertFalse(NativeSpaceTransitionGuard.isMissionControlVisible([ordinary], screenSizes: sizes, bundleIdentifierForPID: bundle))
        }
    }

    func testOrdinaryWindowsNeedNoBundleLookup() {
        var lookups = 0
        let rows: [[String: Any]] = (0..<50).map { [kCGWindowOwnerPID as String: $0, kCGWindowLayer as String: 0,
            kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 800, "Height": 600]] }
        XCTAssertFalse(NativeSpaceTransitionGuard.isMissionControlVisible(rows, screenSizes: [CGSize(width: 1920, height: 1080)]) { _ in
            lookups += 1
            return nil
        })
        XCTAssertEqual(lookups, 0, "Only layer-19 windows are looked up")
    }
}
