@testable import AppBundle
import AppKit
import Metal
import QuartzCore
import XCTest

/// Hardware-backed integration test; does not capture or manipulate the desktop.
final class WorkspaceSwipeRenderingTest: XCTestCase {
    @MainActor
    func testRenderedSpringStaysBoundedAndFinishesInBothDirections() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Offscreen Core Animation rendering requires a Metal device")
        }
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1024, height: 16, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        defer { renderer.layer = nil }
        let duration = 0.22
        for (from, to, speed): (CGFloat, CGFloat, CGFloat) in [(200, 800, 2000), (800, 200, -2000),
                                                             (200, 800, 50000), (800, 200, -50000),
                                                             (200, 800, 0), (800, 200, 0)] {
            let root = CALayer()
            root.frame = CGRect(x: 0, y: 0, width: 1024, height: 16)
            root.backgroundColor = NSColor.black.cgColor
            let marker = CALayer()
            marker.bounds = CGRect(x: 0, y: 0, width: 8, height: 16)
            marker.position = CGPoint(x: 512, y: 8)
            marker.backgroundColor = NSColor.red.cgColor
            marker.transform = CATransform3DMakeTranslation(to - 512, 0, 0)
            root.addSublayer(marker)
            renderer.layer = root
            renderer.bounds = root.bounds
            let animation = WorkspaceSwipePreviewGeometry.settlingAnimation(from: from - 512, to: to - 512, speed: speed, duration: duration)
            let start = CACurrentMediaTime()
            animation.beginTime = start
            // Keep the final animated value visible to measure the error before removal.
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            marker.add(animation, forKey: "spring")
            CATransaction.flush()
            var previous = from
            let finalFrame = Int(ceil(animation.duration * 120))
            for frame in 0...finalFrame {
                renderer.beginFrame(atTime: start + Double(frame) / 120, timeStamp: nil)
                renderer.addUpdate(root.bounds)
                renderer.render()
                renderer.endFrame()
                let barrier = try XCTUnwrap(queue.makeCommandBuffer())
                barrier.commit()
                barrier.waitUntilCompleted()
                XCTAssertEqual(barrier.status, .completed, "Offscreen GPU rendering failed: \(String(describing: barrier.error))")
                var pixels = [UInt8](repeating: 0, count: 1024 * 16 * 4)
                pixels.withUnsafeMutableBytes {
                    texture.getBytes($0.baseAddress!, bytesPerRow: 1024 * 4, from: MTLRegionMake2D(0, 0, 1024, 16), mipmapLevel: 0)
                }
                let red = (0..<1024).filter { pixels[(8 * 1024 + $0) * 4 + 2] > 128 && pixels[(8 * 1024 + $0) * 4] < 40 }
                XCTAssertFalse(red.isEmpty, "Spring left the render target at frame \(frame)")
                guard !red.isEmpty else { continue }
                let position = red.map { Double($0) + 0.5 }.reduce(0, +) / Double(red.count)
                XCTAssertGreaterThanOrEqual(position, min(from, to) - 0.5)
                XCTAssertLessThanOrEqual(position, max(from, to) + 0.5)
                XCTAssertGreaterThanOrEqual((position - previous) * (to > from ? 1 : -1), -0.5)
                if frame == finalFrame { XCTAssertEqual(position, to, accuracy: 0.5) }
                previous = position
            }
            renderer.layer = nil
        }
    }

}
