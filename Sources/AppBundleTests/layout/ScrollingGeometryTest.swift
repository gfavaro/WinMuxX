@testable import AppBundle
import AppKit
import XCTest

/// Isolated geometry tests that do not require AX or running applications.
final class ScrollingGeometryTest: XCTestCase {
    private func makeInput(
        offset: CGFloat = 0,
        widths: [CGFloat] = [0.5, 0.5, 0.5],
        leftWall: Bool = false,
        rightWall: Bool = false,
        preview: CGFloat = 25,
        minimum: CGFloat = 0,
        sheetOffset: CGFloat? = nil
    ) -> ScrollingWorkspaceGeometryInput {
        .init(
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            parkingBounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            offset: offset,
            columns: widths.map { .init(preferredWidth: $0, minimumWidth: minimum) },
            horizontalGap: 0, outerLeft: 0, outerRight: 0,
            leftWall: leftWall, rightWall: rightWall, preview: preview,
            sheetOffset: sheetOffset
        )
    }

    func testEmptyStripHasZeroRange() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(widths: []))
        XCTAssertTrue(result.columns.isEmpty)
        XCTAssertEqual(result.clampedOffset, 0)
        XCTAssertEqual(result.offsetRange.lowerBound, 0)
        XCTAssertEqual(result.offsetRange.upperBound, 0)
    }

    func testThreeColumnsScrollWithinLogicalRangeAndParkOutsideViewport() {
        let first = calculateScrollingWorkspaceGeometry(makeInput())
        XCTAssertEqual(first.area.minX, 25)
        XCTAssertEqual(first.area.width, 950)
        XCTAssertEqual(first.columns.map(\.spanWidth), [500, 500, 500])
        XCTAssertEqual(first.offsetRange.lowerBound, 0)
        XCTAssertEqual(first.offsetRange.upperBound, 550)
        XCTAssertEqual(first.columns[2].visibility, .rightPreview)
        XCTAssertEqual(first.columns[2].physicalFrame.minX, 999, "The partial column already occupies the right edge")

        let last = calculateScrollingWorkspaceGeometry(makeInput(offset: 10_000))
        XCTAssertEqual(last.clampedOffset, 550)
        XCTAssertEqual(last.columns[0].visibility, .leftPreview)
        XCTAssertEqual(last.columns[0].physicalFrame.maxX, 1, "The partial column already occupies the left edge")
        XCTAssertEqual(last.columns[2].visibility, .visible)
    }

    func testAdjacentDisplayWallKeepsParkedWindowOnItsOwnDisplay() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(rightWall: true))
        XCTAssertEqual(result.columns[2].visibility, .parkedRight)
        XCTAssertEqual(result.columns[2].physicalFrame.maxX, 1000)
        XCTAssertGreaterThanOrEqual(result.columns[2].physicalFrame.minX, 0)
    }

    func testNarrowStripCentersWithoutScrolling() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(offset: 100, widths: [1]))
        XCTAssertEqual(result.columns.count, 1)
        XCTAssertEqual(result.clampedOffset, 0)
        XCTAssertEqual(result.columns[0].logicalFrame.width, result.area.width)
    }

    func testFractionsFillUsableWidthOnEitherSideOfSidebar() {
        for sidebarOnLeft in [true, false] {
            for count in [2, 3] {
                let bounds = CGRect(x: sidebarOnLeft ? 240 : 0, y: 0, width: 1201, height: 700)
                let geometry = calculateScrollingWorkspaceGeometry(.init(
                    bounds: bounds, parkingBounds: CGRect(x: 0, y: 0, width: 1441, height: 700),
                    offset: 0, columns: Array(repeating: .init(preferredWidth: 1 / CGFloat(count), minimumWidth: 0), count: count),
                    horizontalGap: 8, outerLeft: sidebarOnLeft ? 240 : 0, outerRight: sidebarOnLeft ? 0 : 240,
                    leftWall: false, rightWall: false, preview: 14))
                let frames = geometry.columns.map(\.physicalFrame)
                XCTAssertEqual(geometry.area, bounds)
                XCTAssertEqual(geometry.offsetRange, 0...0)
                XCTAssertEqual(frames.first?.minX, bounds.minX)
                XCTAssertEqual(frames.last?.maxX, bounds.maxX)
                for frame in frames {
                    XCTAssertEqual(frame.width, (1201 - 8 * CGFloat(count - 1)) / CGFloat(count), accuracy: 1)
                }
                for (left, right) in zip(frames, frames.dropFirst()) {
                    XCTAssertEqual(right.minX - left.maxX, 8)
                }
            }
        }
    }

    func testMinimumWindowWidthOverridesPreferredShare() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(widths: [0.2, 0.2], minimum: 600))
        XCTAssertEqual(result.columns.map(\.spanWidth), [600, 600])
        XCTAssertEqual(result.offsetRange.upperBound, 250)
    }

    func testNonfiniteInputDoesNotPoisonGeometry() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(offset: .nan, widths: [.nan, .infinity], preview: .nan))
        XCTAssertTrue(result.clampedOffset.isFinite)
        XCTAssertTrue(result.columns.allSatisfy { $0.physicalFrame.origin.x.isFinite && $0.physicalFrame.size.width.isFinite })
    }


    func testLargeStripGeometryClampsAllOffsetsAndKeepsFramesFinite() {
        for count in [5, 15, 30, 50] {
            let widths = (0..<count).map { $0.isMultiple(of: 3) ? CGFloat(0.25) : CGFloat(0.6) }
            let initial = calculateScrollingWorkspaceGeometry(makeInput(widths: widths))
            XCTAssertEqual(initial.columns.count, count)
            XCTAssertGreaterThanOrEqual(initial.offsetRange.upperBound, initial.offsetRange.lowerBound)
            for requested in [-10_000.0, 0, 150, 10_000.0] {
                let geometry = calculateScrollingWorkspaceGeometry(makeInput(offset: requested, widths: widths))
                XCTAssertTrue(geometry.offsetRange.contains(geometry.clampedOffset))
                XCTAssertEqual(geometry.stackingOrder.count, count)
                XCTAssertEqual(Set(geometry.stackingOrder).count, count)
                for column in geometry.columns {
                    XCTAssertTrue(column.logicalFrame.minX.isFinite)
                    XCTAssertTrue(column.physicalFrame.minX.isFinite)
                    XCTAssertGreaterThan(column.physicalFrame.width, 0)
                }
            }
        }
    }

    func testParkingAgainstBothAdjacentDisplayWallsRemainsInsideDisplay() {
        for requested in [0.0, 500, 10_000.0] {
            let geometry = calculateScrollingWorkspaceGeometry(
                makeInput(offset: requested, widths: Array(repeating: 0.6, count: 12),
                          leftWall: true, rightWall: true))
            for column in geometry.columns {
                XCTAssertGreaterThanOrEqual(column.physicalFrame.minX, geometry.area.minX - 1)
                XCTAssertLessThanOrEqual(column.physicalFrame.maxX, geometry.area.maxX + 1)
            }
        }
    }


    func testSmallerPreviewPreservesColumnSizesAndRecoversUsableWidth() {
        func layout(_ preview: CGFloat) -> ScrollingWorkspaceGeometry {
            calculateScrollingWorkspaceGeometry(.init(
                bounds: CGRect(x: 8, y: 0, width: 984, height: 700),
                parkingBounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
                offset: 0,
                columns: [0.49, 0.49, 0.49, 0.49].map { .init(preferredWidth: $0, minimumWidth: 0) },
                horizontalGap: 8, outerLeft: 8, outerRight: 8,
                leftWall: false, rightWall: false, preview: preview))
        }
        let wide = layout(25)
        let compact = layout(14)
        XCTAssertEqual(wide.area.minX, 29)
        XCTAssertEqual(compact.area.minX, 18)
        XCTAssertGreaterThan(compact.area.width, wide.area.width)
        XCTAssertEqual(compact.columns[0].physicalFrame.width, wide.columns[0].physicalFrame.width,
                       "Preview gutters change the viewport without shrinking columns")
        XCTAssertEqual(compact.columns[1].logicalFrame.minX - compact.columns[0].logicalFrame.maxX, 8)
        // The fourth column can use only the open space beyond the partially visible column.
        XCTAssertEqual(compact.columns[3].visibility, .rightPreview)
        XCTAssertEqual(compact.columns[3].physicalFrame.minX, 986)
        XCTAssertEqual(wide.columns[3].physicalFrame.minX, wide.columns[1].physicalFrame.maxX)
    }

    func testNoPreviewKeepsParkedColumnsAtScreenEdgeWithoutChangingInterColumnGap() {
        let geometry = calculateScrollingWorkspaceGeometry(.init(
            bounds: CGRect(x: 8, y: 0, width: 984, height: 700),
            parkingBounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            offset: 0,
            columns: [0.6, 0.6, 0.6].map { .init(preferredWidth: $0, minimumWidth: 0) },
            horizontalGap: 8, outerLeft: 8, outerRight: 8,
            leftWall: false, rightWall: false, preview: 0))
        XCTAssertEqual(geometry.area.minX, 8)
        XCTAssertEqual(geometry.area.width, 984)
        XCTAssertEqual(geometry.columns.last?.physicalFrame.minX, 1000)
        XCTAssertEqual(geometry.columns[1].logicalFrame.minX - geometry.columns[0].logicalFrame.maxX, 8)
    }

    func testSheetOffsetExtendsAllowedRangeTemporarily() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(offset: -80, sheetOffset: -80))
        XCTAssertEqual(result.offsetRange.lowerBound, -80)
        XCTAssertEqual(result.clampedOffset, -80)
        let settled = calculateScrollingWorkspaceGeometry(makeInput(offset: -80))
        XCTAssertEqual(settled.clampedOffset, 0)
    }

    func testFiftyColumnsKeepOrderGapsAndBoundPreviewsAtEveryOffset() {
        let widths: [CGFloat] = (0..<50).map { [0.25, 0.3333, 0.5, 0.6667, 1.0][$0 % 5] }
        for offset in stride(from: CGFloat(-500), through: 30_000, by: 1_250) {
            let geometry = calculateScrollingWorkspaceGeometry(.init(
                bounds: CGRect(x: 8, y: 0, width: 1904, height: 1000),
                parkingBounds: CGRect(x: 0, y: 0, width: 1920, height: 1000),
                offset: offset,
                columns: widths.map { .init(preferredWidth: $0, minimumWidth: 0) },
                horizontalGap: 8, outerLeft: 8, outerRight: 8,
                leftWall: false, rightWall: false, preview: 14))
            XCTAssertEqual(geometry.columns.count, 50)
            XCTAssertTrue(geometry.offsetRange.contains(geometry.clampedOffset), "offset \(offset)")
            for (previous, column) in zip(geometry.columns, geometry.columns.dropFirst()) {
                XCTAssertEqual(column.logicalFrame.minX - previous.logicalFrame.maxX, 8, accuracy: 1,
                               "Columns stay in order with one gap between them (offset \(offset))")
            }
            for column in geometry.columns {
                switch column.visibility {
                    case .rightPreview where column.logicalFrame.minX >= geometry.area.maxX:
                        XCTAssertTrue((1920 - 14...1919).contains(column.physicalFrame.minX))
                    case .leftPreview where column.logicalFrame.maxX <= geometry.area.minX:
                        XCTAssertTrue((1...14).contains(column.physicalFrame.maxX))
                    default: break
                }
            }
            XCTAssertEqual(Set(geometry.stackingOrder).count, 50, "Every column appears once in the stacking order")
        }
    }

    func testUnoccupiedEdgeKeepsFullPreview() {
        let geometry = calculateScrollingWorkspaceGeometry(makeInput(widths: [0.95, 0.5]))
        XCTAssertEqual(geometry.columns[0].physicalFrame.maxX, geometry.area.maxX)
        XCTAssertEqual(geometry.columns[1].physicalFrame.minX, 975)
    }

    func testAZeroPreviewStillLeavesOnePointSoMacOSDoesNotPullTheWindowBack() {
        XCTAssertEqual(effectiveEdgePreview(0), 1)
        XCTAssertEqual(effectiveEdgePreview(14), 14)
        let geometry = calculateScrollingWorkspaceGeometry(.init(
            bounds: CGRect(x: 8, y: 0, width: 984, height: 700),
            parkingBounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            offset: 0,
            columns: [0.6, 0.6, 0.6].map { .init(preferredWidth: $0, minimumWidth: 0) },
            horizontalGap: 8, outerLeft: 8, outerRight: 8,
            leftWall: false, rightWall: false, preview: effectiveEdgePreview(0)))
        let parked = geometry.columns[2]
        XCTAssertEqual(parked.visibility, .rightPreview)
        XCTAssertEqual(parked.physicalFrame.minX, 999, "One point stays on the display")
    }
}
