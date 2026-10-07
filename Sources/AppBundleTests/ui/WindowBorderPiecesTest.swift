import AppKit
import PrivateApi
import XCTest

final class WindowBorderPiecesTest: XCTestCase {
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
