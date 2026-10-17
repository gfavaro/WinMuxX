@testable import AppBundle
import AppKit
import XCTest

@MainActor final class PerformanceStateTest: XCTestCase {
    func testMinimumSizesSurviveNewStoreAndReset() throws {
        let suite = "WinMuxX.PerformanceTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistedAppMinimums(defaults: defaults)
        store.remember(CGSize(width: 640, height: 0), for: "test.app")
        let reopened = PersistedAppMinimums(defaults: defaults)
        XCTAssertEqual(reopened.size(for: "test.app"), CGSize(width: 640, height: 0))
        reopened.remember(.zero, for: "test.app")
        XCTAssertNil(PersistedAppMinimums(defaults: defaults).size(for: "test.app"))
        reopened.remember(CGSize(width: 200, height: 200), for: "test.app")
        reopened.reset()
        XCTAssertTrue(PersistedAppMinimums(defaults: defaults).isEmpty)
    }

    func testMinimumStoreRejectsInvalidEvidence() throws {
        let suite = "WinMuxX.PerformanceTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistedAppMinimums(defaults: defaults)
        store.remember(CGSize(width: -1, height: 20), for: "bad")
        store.remember(CGSize(width: CGFloat.nan, height: 20), for: "bad")
        XCTAssertNil(store.size(for: "bad"))
    }

    func testRestingFrameOnlyMatchesSameRequestAndUnmovedWindow() {
        var state = WindowMotionRestingFrames()
        let asked = CGRect(x: 10, y: 20, width: 600, height: 400)
        let got = CGRect(x: 10, y: 20, width: 605, height: 405)
        state.record(1, asked: asked, got: got)
        XCTAssertTrue(state.matches(1, asked: asked, actual: got))
        XCTAssertFalse(state.matches(1, asked: asked.offsetBy(dx: 10, dy: 0), actual: got))
        XCTAssertFalse(state.matches(1, asked: asked, actual: got.offsetBy(dx: 10, dy: 0)))
        state.forget(1)
        XCTAssertFalse(state.matches(1, asked: asked, actual: got))
    }
}
