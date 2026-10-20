@testable import AppBundle
import Darwin
import XCTest

final class RecoveryProcessLaunchDateTest: XCTestCase {
    func testCurrentProcessHasAStableKernelBirthTime() throws {
        let first = try XCTUnwrap(recoveryProcessLaunchDate(getpid()))
        XCTAssertEqual(recoveryProcessLaunchDate(getpid()), first)
        XCTAssertLessThanOrEqual(first, Date())
        XCTAssertGreaterThan(first.timeIntervalSince1970, 0)
    }

    func testUnavailableProcessDoesNotProduceAnIdentity() {
        XCTAssertNil(recoveryProcessLaunchDate(Int32.max))
        XCTAssertNil(recoveryProcessLaunchDate(-1))
    }
}
