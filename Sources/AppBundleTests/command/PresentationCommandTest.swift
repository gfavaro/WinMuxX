import XCTest
@testable import AppBundle
import Common

final class PresentationCommandTest: XCTestCase {
    @MainActor
    func testPresentationModesAndExplicitWindowTargetParseWithoutDefaultBinding() throws {
        for command in ["presentation", "presentation on", "presentation off", "presentation toggle"] {
            XCTAssertNil(parseCommand(command).errorOrNil, command)
        }

        let explicit = try XCTUnwrap(parseCommand("presentation on --window-id 417").cmdOrNil as? PresentationCommand)
        XCTAssertEqual(explicit.args.action, .on)
        XCTAssertTrue(explicit.isPresentation)
        XCTAssertFalse(explicit.shouldResetClosedWindowsCache)
        XCTAssertNotNil(parseCommand("presentation sideways").errorOrNil)
        XCTAssertNotNil(parseCommand("presentation --unknown").errorOrNil)

        let defaultCommands = defaultConfig.modes[mainModeId]?.bindings.values.flatMap(\.commands) ?? []
        XCTAssertFalse(defaultCommands.contains { $0 is PresentationCommand })
    }
}
