@testable import AppBundle
import AppKit
import XCTest

final class MissionControlBorderSuppressionTest: XCTestCase {
    func testDragTrackingExpiresAtRestAndRenewsOnlyChangedWindow() {
        var tracking = WindowBorderMotionTracking()
        tracking.note(1, at: 10)
        tracking.note(2, at: 10.1)
        XCTAssertEqual(Set(tracking.active(at: 10.14, mouseDown: true)), [1, 2])
        XCTAssertEqual(tracking.active(at: 10.2, mouseDown: true), [2])
        tracking.note(2, at: 10.2)
        XCTAssertEqual(tracking.active(at: 10.3, mouseDown: true), [2])
        XCTAssertTrue(tracking.active(at: 10.4, mouseDown: true).isEmpty)
    }

    func testDragReleaseDeliversOneFinalUpdateThenStops() {
        var tracking = WindowBorderMotionTracking()
        tracking.note(42, at: 1)
        XCTAssertEqual(tracking.active(at: 1.05, mouseDown: false), [42])
        XCTAssertTrue(tracking.active(at: 1.06, mouseDown: false).isEmpty)
        tracking.note(99, at: 2)
        XCTAssertEqual(tracking.active(at: 2.01, mouseDown: true), [99])
    }

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
        XCTAssertLessThan(panel.frame.height, 104)
        XCTAssertEqual(border.windowIds.count, 4)
        border.update(frame: frame.offsetBy(dx: 10, dy: 0), active: false, settings: settings)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(panel.frame.minX, -19992)
        border.destroy()
        XCTAssertEqual(border.windowId, 0)
    }

    @MainActor
    func testFallbackEdgesKeepExactFramesAcrossDisplayBoundary() throws {
        let border = WindowBorder(target: 0, createNativeBorder: { _, _ in false })
        defer { border.destroy() }
        var settings = WindowBordersConfig()
        settings.width = 4
        let frame = CGRect(x: 836, y: -1408, width: 1694, height: 1405)
        border.update(frame: frame, active: true, settings: settings)
        let outer = CGRect(x: frame.minX, y: mainMonitor.height - frame.maxY,
                           width: frame.width, height: frame.height).insetBy(dx: -4, dy: -4)
        XCTAssertEqual(border.windowIds.count, 4)
        for id in border.windowIds {
            let panel = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == Int(id) })
            XCTAssertTrue(outer.contains(panel.frame))
            XCTAssertEqual(panel.constrainFrameRect(panel.frame, to: NSScreen.main), panel.frame)
        }
    }

    @MainActor
    func testDrawingFailureReleasesNativeHandleAndReusesFallback() {
        var creations = 0
        var destructions = 0
        let border = WindowBorder(target: 0, createNativeBorder: { _, handle in
            creations += 1
            handle = OpaquePointer(bitPattern: 1)
            return true
        }, updateNativeBorder: { _, _, _, _, _, _, _ in false }, destroyNativeBorder: { _ in
            destructions += 1
        })
        var settings = WindowBordersConfig()
        settings.width = 2
        let frame = CGRect(x: -20000, y: -20000, width: 100, height: 100)
        border.update(frame: frame, active: true, settings: settings)
        XCTAssertEqual(destructions, 1)
        let fallbackIds = border.windowIds
        XCTAssertEqual(fallbackIds.count, 4)
        border.update(frame: frame.offsetBy(dx: 10, dy: 0), active: false, settings: settings)
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(border.windowIds, fallbackIds)
        border.destroy()
        border.destroy()
        XCTAssertTrue(border.windowIds.isEmpty)
        XCTAssertEqual(destructions, 1)
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
