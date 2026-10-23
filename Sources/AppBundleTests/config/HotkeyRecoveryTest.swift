@testable import AppBundle
import XCTest

@MainActor
final class HotkeyRecoveryTest: XCTestCase {
    func testRetriesUntilInstallationRecovers() async {
        var waits: [Duration] = []
        var attempts = 0
        let result = await runHotkeyRecovery(
            delays: [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)],
            shouldContinue: { true },
            wait: { waits.append($0) },
            attempt: {
                attempts += 1
                return attempts == 3
            }
        )

        XCTAssertEqual(result, .recovered)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(waits, [.milliseconds(500), .seconds(1), .seconds(2)])
    }

    func testStopsAfterBoundedFailures() async {
        var attempts = 0
        let result = await runHotkeyRecovery(
            delays: [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)],
            shouldContinue: { true },
            wait: { _ in },
            attempt: { attempts += 1; return false }
        )

        XCTAssertEqual(result, .exhausted)
        XCTAssertEqual(attempts, 4)
    }

    func testStopsWhenBackendIsNoLongerRequired() async {
        var checks = 0
        var attempts = 0
        let result = await runHotkeyRecovery(
            delays: [.milliseconds(500), .seconds(1)],
            shouldContinue: { checks += 1; return checks == 1 },
            wait: { _ in },
            attempt: { attempts += 1; return false }
        )

        XCTAssertEqual(result, .noLongerRequired)
        XCTAssertEqual(attempts, 1)
    }

    func testStopsAfterCancellation() async {
        let result = await runHotkeyRecovery(
            delays: [.milliseconds(500)],
            shouldContinue: { true },
            wait: { _ in throw CancellationError() },
            attempt: { XCTFail("A cancelled recovery must not attempt installation"); return false }
        )

        XCTAssertEqual(result, .cancelled)
    }
}
