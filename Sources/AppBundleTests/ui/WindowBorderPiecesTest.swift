@testable import AppBundle
import AppKit
import PrivateApi
import XCTest

final class WindowBorderPiecesTest: XCTestCase {
    func testScreenPartitionsStayOnBackingPixelsAtFractionalAndNegativeOrigins() {
        for scale: CGFloat in [1, 2] {
            for origin: CGFloat in [-1800.25, -0.75, 0.25, 100.5] {
                for width: CGFloat in [0.5, 4, 4.5] {
                    let frame = CGRect(x: origin, y: origin + 0.25, width: 800.5, height: 600.5)
                    let aligned = pixelAlignedWindowBorderFrame(frame, width: width, scale: scale)
                    XCTAssertEqual(aligned.size, frame.size)
                    XCTAssertLessThanOrEqual(abs(aligned.minX - frame.minX), 0.5 / scale)
                    XCTAssertLessThanOrEqual(abs(aligned.minY - frame.minY), 0.5 / scale)
                    XCTAssertEqual(pixelAlignedWindowBorderFrame(aligned, width: width, scale: scale), aligned)
                    let outer = aligned.insetBy(dx: -width, dy: -width)
                    for index in 0..<4 {
                        let piece = winmux_border_piece(outer.size, 19, Float(width), Float(scale), Int32(index))
                        for coordinate in [outer.minX + piece.minX, outer.minY + piece.minY] {
                            XCTAssertEqual(coordinate * scale, (coordinate * scale).rounded(), accuracy: 0.000001)
                        }
                    }
                }
            }
        }
    }

    func testPartitionsAreDisjointAndContainTheRingAtBothScales() {
        for scale: Float in [1, 2] {
            for size in [CGSize(width: 1700, height: 1400), CGSize(width: 20, height: 14), CGSize(width: 5, height: 3), CGSize(width: 5, height: 100), CGSize(width: 160.5, height: 100.5)] {
                for width: Float in [0.5, 4.5, 12] {
                    let bounds = CGRect(x: 0, y: 0, width: ceil(size.width * CGFloat(scale)) / CGFloat(scale), height: ceil(size.height * CGFloat(scale)) / CGFloat(scale))
                    let pieces = (0..<4).map { winmux_border_piece(size, 12, width, scale, Int32($0)) }
                    for (i, piece) in pieces.enumerated() {
                        XCTAssertTrue(bounds.contains(piece))
                        for other in pieces.dropFirst(i + 1) {
                            let overlap = piece.intersection(other)
                            XCTAssertTrue(overlap.isNull || overlap.isEmpty)
                        }
                    }
                    if size.width > 1000 {
                        let area = pieces.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
                        XCTAssertLessThan(area, size.width * size.height * 0.1)
                    }
                }
            }
        }
    }

    func testPieceRenderingMatchesFullRoundedRingIncludingTranslucentSeams() throws {
        for scale: Float in [1, 2] {
            for width: Float in [0.5, 4.5, 12] {
                for size in [CGSize(width: 160, height: 100), CGSize(width: 20, height: 14), CGSize(width: 5, height: 3), CGSize(width: 5, height: 100), CGSize(width: 160.5, height: 100.5)] {
                    for rgba: UInt32 in [0xE1E3E4FF, 0x494D6480] {
                        let expected = try render(size: size, scale: scale, width: width, rgba: rgba, pieces: false)
                        let actual = try render(size: size, scale: scale, width: width, rgba: rgba, pieces: true)
                        XCTAssertEqual(actual, expected, "size=\(size) scale=\(scale) width=\(width) rgba=\(rgba)")
                    }
                }
            }
        }
    }

    func testContinuousGeometryCoversObservedCornerFissure() {
        // Dark pixels sampled from the user's System Settings top-left corner,
        // relative to the outer border origin; independent of generated paths.
        let samples: [(CGFloat, CGFloat)] = [(13, 5), (14, 5), (11, 6), (10, 7), (9, 8),
            (8, 9), (7, 10), (6, 11), (5, 13), (5, 14), (4, 16), (4, 17), (4, 18), (4, 19), (4, 20)]
        let geometry = WindowBorderGeometry(size: CGSize(width: 764, height: 796), radius: 16, width: 4, scale: 1)
        for (x, y) in samples {
            XCTAssertTrue(geometry.path.contains(CGPoint(x: x + 0.5, y: y + 0.5), using: .evenOdd), "sample \(x),\(y)")
        }
    }

    func testOverlapIsLimitedToHalfBackingPixel() {
        for scale: CGFloat in [1, 2] {
            let geometry = WindowBorderGeometry(size: CGSize(width: 200, height: 100), radius: 16, width: 4, scale: scale)
            let innerEdge = 4 + 0.5 / scale
            XCTAssertTrue(geometry.path.contains(CGPoint(x: innerEdge - 0.01, y: 50), using: .evenOdd))
            XCTAssertFalse(geometry.path.contains(CGPoint(x: innerEdge + 0.01, y: 50), using: .evenOdd))
        }
    }

    func testContinuousPiecesMatchFullPathWithoutTranslucentSeams() throws {
        for scale: CGFloat in [1, 2] {
            for size in [CGSize(width: 160, height: 100), CGSize(width: 160.5, height: 100.5),
                         CGSize(width: 20, height: 14), CGSize(width: 5, height: 100)] {
                for width: CGFloat in [0.5, 4.5, 12] {
                    let geometry = WindowBorderGeometry(size: size, radius: 16, width: width, scale: scale)
                    let full = try renderContinuous(geometry, pieces: false)
                    let stitched = try renderContinuous(geometry, pieces: true)
                    XCTAssertEqual(full, stitched, "size=\(size) scale=\(scale) width=\(width)")
                }
            }
        }
    }

    func testTabGroupCornersAndTranslucentPiecesMatchAtBothScales() throws {
        for scale: CGFloat in [1, 2] {
            for size in [CGSize(width: 800, height: 600), CGSize(width: 19, height: 12)] {
                for width: CGFloat in [0.5, 4, 12] {
                    let geometry = WindowBorderGeometry(size: size, radius: 12, width: width,
                        scale: scale, bottomRadius: 19)
                    XCTAssertEqual(geometry.key.partitionRadius, 19)
                    XCTAssertEqual(try renderContinuous(geometry, pieces: false),
                        try renderContinuous(geometry, pieces: true))
                }
            }
        }
        // The tab strip's tighter top corners and the app shell's broader bottom
        // corners must stay distinguishable, rather than becoming a uniform ring.
        let geometry = WindowBorderGeometry(size: CGSize(width: 800, height: 600),
            radius: 12, width: 4, scale: 2, bottomRadius: 19)
        XCTAssertNotEqual(geometry.path.contains(CGPoint(x: 6, y: 6), using: .evenOdd),
            geometry.path.contains(CGPoint(x: 6, y: 594), using: .evenOdd))
    }

    private func renderContinuous(_ geometry: WindowBorderGeometry, pieces: Bool) throws -> Data {
        let key = geometry.key
        let width = Int(ceil(key.size.width * key.scale))
        let height = Int(ceil(key.size.height * key.scale))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: key.scale, y: key.scale)
        if pieces {
            for index in 0..<4 {
                let piece = winmux_border_piece(key.size, Float(key.partitionRadius), Float(key.width), Float(key.scale), Int32(index))
                if piece.isEmpty { continue }
                context.saveGState()
                context.translateBy(x: piece.minX, y: piece.minY)
                winmux_border_draw_path(context, piece, geometry.path, 0x494D6480)
                context.restoreGState()
            }
        } else {
            context.setFillColor(red: 73.0 / 255, green: 77.0 / 255, blue: 100.0 / 255, alpha: 128.0 / 255)
            context.addPath(geometry.path)
            context.drawPath(using: .eoFill)
        }
        return Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
    }

    private func render(size: CGSize, scale: Float, width: Float, rgba: UInt32, pieces: Bool) throws -> Data {
        let pixelWidth = Int(ceil(size.width * CGFloat(scale)))
        let pixelHeight = Int(ceil(size.height * CGFloat(scale)))
        let context = try XCTUnwrap(CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                            bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        if pieces {
            for index in 0..<4 {
                let piece = winmux_border_piece(size, 12, width, scale, Int32(index))
                if piece.isEmpty { continue }
                context.saveGState()
                context.translateBy(x: piece.minX, y: piece.minY)
                winmux_border_draw(context, size, piece, 12, rgba, width)
                context.restoreGState()
            }
        } else {
            let outer = CGRect(origin: .zero, size: size)
            let path = CGMutablePath()
            let radius = min(CGFloat(12 + width), min(size.width, size.height) / 2)
            path.addRoundedRect(in: outer, cornerWidth: radius, cornerHeight: radius)
            let inner = outer.insetBy(dx: CGFloat(width), dy: CGFloat(width))
            if !inner.isEmpty {
                let innerRadius = min(CGFloat(12), min(inner.width, inner.height) / 2)
                path.addRoundedRect(in: inner, cornerWidth: innerRadius, cornerHeight: innerRadius)
            }
            context.setFillColor(red: CGFloat((rgba >> 24) & 255) / 255, green: CGFloat((rgba >> 16) & 255) / 255,
                                 blue: CGFloat((rgba >> 8) & 255) / 255, alpha: CGFloat(rgba & 255) / 255)
            context.addPath(path)
            context.drawPath(using: .eoFill)
        }
        return Data(bytes: try XCTUnwrap(context.data), count: pixelWidth * pixelHeight * 4)
    }
}
