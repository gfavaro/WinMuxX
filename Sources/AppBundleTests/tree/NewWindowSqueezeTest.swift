@testable import AppBundle
import XCTest

final class NewWindowSqueezeTest: XCTestCase {
    func testSplitsWhenBothHalvesFitTheLearnedMinimums() {
        XCTAssertFalse(newWindowSplitWouldSqueeze(tile: CGSize(width: 1700, height: 1000),
            gap: CGSize(width: 10, height: 10), minimums: [CGSize(width: 800, height: 400)]))
        XCTAssertFalse(newWindowSplitWouldSqueeze(tile: CGSize(width: 1700, height: 1000),
            gap: .zero, minimums: []), "Without learned minimums the window splits as before")
    }

    func testJoinsWhenEitherAppWouldGoBelowItsMinimum() {
        let tile = CGSize(width: 1000, height: 1000)
        XCTAssertTrue(newWindowSplitWouldSqueeze(tile: tile, gap: CGSize(width: 10, height: 10),
            minimums: [CGSize(width: 300, height: 300), CGSize(width: 500, height: 200)]),
            "A square tile splits side by side: 495 points is narrower than 500")
        XCTAssertTrue(newWindowSplitWouldSqueeze(tile: CGSize(width: 600, height: 900),
            gap: CGSize(width: 10, height: 10), minimums: [CGSize(width: 100, height: 500)]),
            "A tall tile splits top and bottom, so the height decides")
    }
}
