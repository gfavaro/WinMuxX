@testable import AppBundle
import AppKit
import XCTest

final class MissionControlBorderSuppressionTest: XCTestCase {
    @MainActor
    func testUnavailablePrivateRendererFallsBackWithoutRepeatedCreationAttempts() throws {
        let target = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        target.isReleasedWhenClosed = false
        target.orderFront(nil)
        defer { target.close() }
        var attempts = 0
        let border = WindowBorder(target: UInt32(target.windowNumber), createNativeBorder: { _, _ in
            attempts += 1
            return false
        })
        defer { border.destroy() }
        var settings = WindowBordersConfig()
        settings.width = 2
        let frame = CGRect(x: -20000, y: -20000, width: 100, height: 100)
        border.update(frame: frame, active: true, settings: settings)
        let panel = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == Int(border.windowId) })
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertEqual(panel.frame.width, 104)
        border.update(frame: frame.offsetBy(dx: 10, dy: 0), active: false, settings: settings)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(panel.frame.minX, -19992)
        border.destroy()
        XCTAssertEqual(border.windowId, 0)
    }

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
