import CoreGraphics
import Foundation
import XCTest
@testable import NativeSpaces

final class NativeSpaceNavigationTests: XCTestCase {
    // External: desktop, fullscreen, desktop. Built-in: two desktops.
    private let displays = [
        NativeSpaceDisplay(identifier: "external", activeSpaceID: "1", spaces: [
            NativeSpace(id: "1", uuid: "a", type: 0), NativeSpace(id: "9", uuid: "full", type: 4),
            NativeSpace(id: "2", uuid: "b", type: 0),
        ]),
        NativeSpaceDisplay(identifier: "built-in", activeSpaceID: "4", spaces: [
            NativeSpace(id: "3", uuid: "c", type: 0), NativeSpace(id: "4", uuid: "d", type: 0),
        ]),
    ]

    func testDesktopNumbersFollowControlNumberAcrossDisplaysSkippingFullscreen() {
        XCTAssertEqual(NativeSpaceNavigation.desktop(number: 2, in: displays),
            NativeSpaceSwitchPlan(displayIdentifier: "external", fromIndex: 0, toIndex: 2, targetSpaceID: "2"))
        XCTAssertEqual(NativeSpaceNavigation.desktop(number: 3, in: displays),
            NativeSpaceSwitchPlan(displayIdentifier: "built-in", fromIndex: 1, toIndex: 0, targetSpaceID: "3"))
        XCTAssertEqual(NativeSpaceNavigation.desktop(number: 4, in: displays)?.isNoop, true)
        XCTAssertNil(NativeSpaceNavigation.desktop(number: 5, in: displays))
        XCTAssertNil(NativeSpaceNavigation.desktop(number: 0, in: displays))
    }

    func testAdjacentFollowsControlArrowIncludingFullscreenSpaces() {
        XCTAssertEqual(NativeSpaceNavigation.adjacent(next: true, wrapAround: false, on: "external", in: displays)?.targetSpaceID, "9")
        XCTAssertNil(NativeSpaceNavigation.adjacent(next: false, wrapAround: false, on: "external", in: displays))
        XCTAssertEqual(NativeSpaceNavigation.adjacent(next: false, wrapAround: true, on: "external", in: displays),
            NativeSpaceSwitchPlan(displayIdentifier: "external", fromIndex: 0, toIndex: 2, targetSpaceID: "2"))
        XCTAssertEqual(NativeSpaceNavigation.adjacent(next: true, wrapAround: true, on: "built-in", in: displays)?.targetSpaceID, "3")
        XCTAssertNil(NativeSpaceNavigation.adjacent(next: true, wrapAround: true, on: "unknown", in: displays))
    }

    func testActiveDesktopNumberIsTheInverseAndNilOnFullscreen() {
        XCTAssertEqual(NativeSpaceNavigation.activeDesktopNumber(on: "external", in: displays), 1)
        XCTAssertEqual(NativeSpaceNavigation.activeDesktopNumber(on: "built-in", in: displays), 4)
        let fullscreen = [NativeSpaceDisplay(identifier: "external", activeSpaceID: "9", spaces: displays[0].spaces)]
        XCTAssertNil(NativeSpaceNavigation.activeDesktopNumber(on: "external", in: fullscreen))
    }

    func testDockSwipePayloadMatchesTheIOHIDLayout() throws {
        XCTAssertEqual(NativeDockSwipe.fixed1616(1), 65536)
        XCTAssertEqual(NativeDockSwipe.fixed1616(-0.000001), -1, "A nonzero value must not round to zero")
        // Gesture fields persist only once the event is typed as a Dock-control swipe.
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.setIntegerValueField(CGEventField(rawValue: 55)!, value: 30)
        event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 23)
        event.setIntegerValueField(CGEventField(rawValue: 132)!, value: 4) // ended
        event.setDoubleValueField(CGEventField(rawValue: 124)!, value: -1)
        let payload = NativeDockSwipe.iohidPayload(event)
        try XCTSkipUnless(event.getIntegerValueField(CGEventField(rawValue: 132)!) == 4,
            "This host's CGEvent does not retain Dock gesture fields")
        guard payload.count == 28 + 40 + 28 else { return XCTFail("Ended swipes carry velocity: \(payload.count) bytes") }
        func u32(_ offset: Int) -> UInt32 { payload.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        XCTAssertEqual(u32(24), 2, "event count")
        XCTAssertEqual(u32(28), 40)
        XCTAssertEqual(u32(32), 23)
        XCTAssertEqual(u32(36), 4 << 24, "phase in the high byte")
        XCTAssertEqual(Int32(bitPattern: u32(28 + 36)), -65536, "swipe progress")
        XCTAssertEqual(u32(68), 28)
        XCTAssertEqual(u32(72), 9)
    }
}
