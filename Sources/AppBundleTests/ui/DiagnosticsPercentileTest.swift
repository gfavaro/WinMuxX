@testable import AppBundle
import XCTest

final class DiagnosticsPercentileTest: XCTestCase {
    func testSummaryReportsNearestRankPercentilesIncludingTheTail() {
        XCTAssertEqual(percentileSummary((1...100).map(Double.init).shuffled()),
                       "count=100 p50=50.0ms p95=95.0ms p99=99.0ms")
        XCTAssertEqual(percentileSummary([7]), "count=1 p50=7.0ms p95=7.0ms p99=7.0ms")
    }
}
