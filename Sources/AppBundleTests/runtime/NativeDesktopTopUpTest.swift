@testable import AppBundle
@testable import NativeSpaces
import XCTest

@MainActor
final class NativeDesktopTopUpTest: XCTestCase {
    private func display(_ id: String, _ spaces: [(String, Int)]) -> NativeSpaceDisplay {
        NativeSpaceDisplay(identifier: id, activeSpaceID: spaces[0].0,
            spaces: spaces.map { NativeSpace(id: $0.0, uuid: "uuid-\($0.0)", type: $0.1) })
    }

    func testTargetIsTheHighestNumberedPersistentWorkspace() {
        XCTAssertEqual(NativeDesktopTopUp.target(["1", "2", "3", "4", "5"]), 5)
        XCTAssertEqual(NativeDesktopTopUp.target(["2", "web", "7"]), 7)
        XCTAssertEqual(NativeDesktopTopUp.target(["web", "0"]), 0)
    }

    func testNextCountsDesktopsOnlyAndUsesTheHomeDisplay() {
        // A full-screen Space (type 4) is not a desktop.
        let displays = [display("built-in", [("1", 0), ("2", 0), ("9", 4)]), display("external", [("3", 0)])]
        XCTAssertEqual(NativeDesktopTopUp.next(displays, target: 3, home: { _ in "external" })?.display, nil)
        let step = NativeDesktopTopUp.next(displays, target: 5, home: { $0 == 4 ? "external" : "built-in" })
        XCTAssertEqual(step?.number, 4)
        XCTAssertEqual(step?.display, "external")
        // A home display that is not connected falls back to the first one.
        XCTAssertEqual(NativeDesktopTopUp.next(displays, target: 5, home: { _ in "gone" })?.display, "built-in")
    }

    func testCreatesOneDesktopPerConfirmedReadAfterTheDisplaysSettle() {
        var clock = ContinuousClock.now
        var created: [String] = []
        var scheduled: [Duration] = []
        let topUp = NativeDesktopTopUp()
        topUp.now = { clock }
        topUp.isAvailable = { true }
        topUp.create = { created.append($0); return UInt64(100 + created.count) }
        let observe = { (displays: [NativeSpaceDisplay]) in
            topUp.observed(displays, target: 3, home: { _ in "main" }) { scheduled.append($0) }
        }

        var spaces = [("1", 0)]
        XCTAssertFalse(observe([display("main", spaces)]))
        XCTAssertEqual(scheduled, [.seconds(1)], "a new display set waits to settle")
        XCTAssertEqual(created, [])

        clock = clock.advanced(by: .seconds(1))
        XCTAssertTrue(observe([display("main", spaces)]))
        XCTAssertEqual(created, ["main"])
        // A read that does not show the new desktop yet creates nothing more.
        XCTAssertFalse(observe([display("main", spaces)]))
        XCTAssertEqual(created.count, 1)

        spaces.append(("101", 0))
        XCTAssertTrue(observe([display("main", spaces)]))
        XCTAssertEqual(created.count, 2)
        spaces.append(("102", 0))
        XCTAssertFalse(observe([display("main", spaces)]))
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(topUp.status, "all 3 configured desktops present")
    }

    func testAFailureStopsUntilReloadOrDisplaysChange() {
        var clock = ContinuousClock.now
        var attempts = 0
        let topUp = NativeDesktopTopUp()
        topUp.now = { clock }
        topUp.settleDelay = .zero
        topUp.isAvailable = { true }
        topUp.create = { _ in attempts += 1; return nil }
        let one = [display("main", [("1", 0)])]
        let observe = { (displays: [NativeSpaceDisplay]) in
            topUp.observed(displays, target: 2, home: { _ in nil }) { _ in }
        }

        XCTAssertFalse(observe(one))
        XCTAssertFalse(observe(one))
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(topUp.status.hasPrefix("stopped"))

        _ = observe(one + [display("external", [("5", 0)])])
        XCTAssertEqual(attempts, 1, "two displays already have two desktops")
        clock = clock.advanced(by: .seconds(1))
        _ = observe(one)
        XCTAssertEqual(attempts, 1, "the stopped display set is unchanged")

        topUp.reset()
        _ = observe(one)
        XCTAssertEqual(attempts, 2)
    }

    func testADesktopThatNeverAppearsStopsAfterTheTimeout() {
        var clock = ContinuousClock.now
        var attempts = 0
        let topUp = NativeDesktopTopUp()
        topUp.now = { clock }
        topUp.settleDelay = .zero
        topUp.isAvailable = { true }
        topUp.create = { _ in attempts += 1; return 77 }
        let one = [display("main", [("1", 0)])]
        XCTAssertTrue(topUp.observed(one, target: 2, home: { _ in nil }) { _ in })
        clock = clock.advanced(by: .seconds(3))
        XCTAssertFalse(topUp.observed(one, target: 2, home: { _ in nil }) { _ in })
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(topUp.status, "stopped: desktop 2 did not appear")
    }
}
