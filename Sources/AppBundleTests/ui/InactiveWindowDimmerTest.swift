@testable import AppBundle
import Common
import XCTest

@MainActor
final class InactiveWindowDimmerTest: WorkspaceTestCase {
    func testDimmingConfigAcceptsZeroToPointEight() {
        XCTAssertEqual(parseConfig("[dimming]\ninactive-windows = 0.3").config.dimming.inactiveWindows, 0.3)
        XCTAssertEqual(parseConfig("").config.dimming.inactiveWindows, 0, "Off by default")
        XCTAssertFalse(parseConfig("[dimming]\ninactive-windows = 0.9").errors.isEmpty)
        XCTAssertFalse(parseConfig("[dimming]\ninactive-windows = -1").errors.isEmpty)
    }

    func testNoPeekWinsOverLightDimming() {
        XCTAssertNil(InactiveWindowDimmer.style(noPeek: false, inactive: 0))
        XCTAssertEqual(InactiveWindowDimmer.style(noPeek: false, inactive: 0.3), .dim(0.3))
        XCTAssertEqual(InactiveWindowDimmer.style(noPeek: true, inactive: 0.3), .noPeek)
    }

    func testNoPeekCommandTogglesAndAcceptsOnOff() async throws {
        defer { InactiveWindowDimmer.shared.setNoPeek(false) }
        func run(_ text: String) async throws -> CmdResult {
            try await XCTUnwrap(parseCommand(text).unwrap().0).run(.defaultEnv, .emptyStdin)
        }
        let on = try await run("no-peek")
        XCTAssertEqual(on.stdout, ["No peek on"])
        XCTAssertTrue(InactiveWindowDimmer.shared.noPeek)
        _ = try await run("no-peek on")
        XCTAssertTrue(InactiveWindowDimmer.shared.noPeek, "on stays on")
        let off = try await run("no-peek toggle")
        XCTAssertEqual(off.stdout, ["No peek off"])
        XCTAssertFalse(InactiveWindowDimmer.shared.noPeek)
        if case .cmd = parseCommand("no-peek sideways") { XCTFail("Unknown action must not parse") }
    }
}
