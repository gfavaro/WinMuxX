@testable import AppBundle
import Common
import XCTest

final class ParkingCornerTest: XCTestCase {
    private func rect(_ x: CGFloat, _ y: CGFloat) -> Rect {
        Rect(topLeftX: x, topLeftY: y, width: 1000, height: 800)
    }

    func testExistingCornerSelectionForDisplayArrangements() {
        let layouts: [([Rect], [OptimalHideCorner])] = [
            ([rect(0, 0)], [.bottomRightCorner]),
            ([rect(0, 0), rect(1000, 0)], [.bottomLeftCorner, .bottomRightCorner]),
            ([rect(0, 0), rect(0, 800)], [.bottomRightCorner, .bottomRightCorner]),
            ([rect(0, 0), rect(1000, 200)], [.bottomLeftCorner, .bottomRightCorner]),
        ]
        for (displays, expected) in layouts {
            for (index, display) in displays.enumerated() {
                XCTAssertEqual(legacyCorner(for: display, displays: displays), expected[index])
                XCTAssertEqual(optimalWorkspaceHideCorner(for: display, displays: displays), expected[index])
            }
        }
    }

    func testExtractionMatchesOriginalExpressionAcrossOffsets() {
        for x in stride(from: -1500, through: 1500, by: 250) {
            for y in stride(from: -1200, through: 1200, by: 200) {
                let displays = [rect(0, 0), rect(CGFloat(x), CGFloat(y))]
                for display in displays {
                    XCTAssertEqual(optimalWorkspaceHideCorner(for: display, displays: displays),
                                   legacyCorner(for: display, displays: displays))
                }
            }
        }
    }

    // Characterizes the original inline expression before extracting the production helper.
    private func legacyCorner(for display: Rect, displays: [Rect]) -> OptimalHideCorner {
        let xOff = display.width * 0.1
        let yOff = display.height * 0.1
        let brc1 = display.bottomRightCorner + CGPoint(x: 2, y: -yOff)
        let brc2 = display.bottomRightCorner + CGPoint(x: -xOff, y: 2)
        let brc3 = display.bottomRightCorner + CGPoint(x: 2, y: 2)
        let blc1 = display.bottomLeftCorner + CGPoint(x: -2, y: -yOff)
        let blc2 = display.bottomLeftCorner + CGPoint(x: xOff, y: 2)
        let blc3 = display.bottomLeftCorner + CGPoint(x: -2, y: 2)
        func contains(_ rect: Rect, _ point: CGPoint) -> Int { rect.contains(point) ? 1 : 0 }
        let important = 10
        return displays.sumOfInt { contains($0, blc1) + contains($0, blc2) + important * contains($0, blc3) } <
            displays.sumOfInt { contains($0, brc1) + contains($0, brc2) + important * contains($0, brc3) }
            ? .bottomLeftCorner : .bottomRightCorner
    }
}
