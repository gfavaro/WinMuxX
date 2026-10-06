@testable import AppBundle
import AppKit
import XCTest

final class MissionControlBorderSuppressionTest: XCTestCase {
    func testRestorationUsesNativeFrameInsteadOfOverviewThumbnail() {
        let real = CGRect(x: 48, y: 42, width: 1658, height: 1065)
        let thumbnail = CGRect(x: 714, y: 609, width: 78, height: 51)
        XCTAssertEqual(resolvedWindowBorderFrame(snapshot: thumbnail, nativeFrame: real), real)
    }

    func testGeometryFallsBackWhenPrivateBoundsAreUnavailable() {
        let snapshot = CGRect(x: 48, y: 42, width: 1658, height: 1065)
        XCTAssertEqual(resolvedWindowBorderFrame(snapshot: snapshot, nativeFrame: nil), snapshot)
    }
    func testEntryAndExitEachTriggerOnceAndRefreshesStaySuppressed() {
        var state = MissionControlBorderState()
        XCTAssertNil(state.update(active: false))
        XCTAssertEqual(state.update(active: true), true)
        XCTAssertTrue(state.active)
        XCTAssertNil(state.update(active: true))
        XCTAssertEqual(state.update(active: false), false)
        XCTAssertFalse(state.active)
        XCTAssertNil(state.update(active: false))
    }

    func testOtherAppsDisplaySizedLevelNineteenWindowDoesNotSuppressBorders() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertFalse(isMissionControlVisible([[
            kCGWindowOwnerPID as String: NSNumber(value: 42),
            kCGWindowLayer as String: NSNumber(value: 19),
            kCGWindowBounds as String: frame.dictionaryRepresentation,
        ]], screenSizes: [frame.size], bundleIdentifierForPID: { _ in "example.other" }))
    }
    func testDisplaySizedWindowManagerLevelNineteenSuppressesBorders() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let entry: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: 42),
            kCGWindowLayer as String: NSNumber(value: 19),
            kCGWindowBounds as String: frame.dictionaryRepresentation,
        ]

        XCTAssertTrue(isMissionControlVisible(
            [entry],
            screenSizes: [frame.size],
            bundleIdentifierForPID: { $0 == 42 ? "com.apple.WindowManager" : nil },
        ))
    }

    func testOrdinaryWindowManagerWindowDoesNotSuppressBorders() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let entry: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: 42),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowBounds as String: frame.dictionaryRepresentation,
        ]

        XCTAssertFalse(isMissionControlVisible(
            [entry],
            screenSizes: [CGSize(width: 1440, height: 900)],
            bundleIdentifierForPID: { _ in "com.apple.WindowManager" },
        ))
    }
}
