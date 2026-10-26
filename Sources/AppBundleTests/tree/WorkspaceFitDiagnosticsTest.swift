import XCTest
@testable import AppBundle

final class WorkspaceFitDiagnosticsTest: XCTestCase {
    func testConfirmedMinimumCanBlockAnExplicitResizeByAxis() {
        XCTAssertTrue(ExplicitResizeMinimumBlock(requested: 400, minimum: 600, dimension: .h).isBlocked)
        XCTAssertFalse(ExplicitResizeMinimumBlock(requested: 599, minimum: 600, dimension: .h).isBlocked)
        XCTAssertFalse(ExplicitResizeMinimumBlock(requested: 800, minimum: 600, dimension: .v).isBlocked)
    }

    func testOnlyMinimumBeyondAvailableAreaIsReported() {
        XCTAssertTrue(layoutMinimumExceedsArea(CGSize(width: 1400, height: 400), available: CGSize(width: 1200, height: 900)))
        XCTAssertTrue(layoutMinimumExceedsArea(CGSize(width: 400, height: 1000), available: CGSize(width: 1200, height: 900)))
        XCTAssertFalse(layoutMinimumExceedsArea(CGSize(width: 900, height: 700), available: CGSize(width: 1200, height: 900)))
    }

    func testIntentionalOffscreenColumnIsNotDiagnosedUnlessItsMinimumExceedsViewport() {
        XCTAssertFalse(scrollingColumnMinimumExceedsViewport(800, viewportWidth: 1000))
        XCTAssertTrue(scrollingColumnMinimumExceedsViewport(1100, viewportWidth: 1000))
    }
}
