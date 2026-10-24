@testable import AppBundle
import AppKit
import Common
import XCTest

/// Measures only our synthetic offscreen surface path. No desktop capture, gestures,
/// AX calls, user configuration writes, or wall-clock pass/fail thresholds.
@MainActor
final class WorkspaceSwipePreviewPerformanceTest: WorkspaceTestCase {
    func testDirectTrackingAndReleaseUseTouchTime() throws {
        let rect = Rect(topLeftX: -20000, topLeftY: -20000, width: 200, height: 100)
        let request = WorkspaceSwipeSnapshotRequest(key: WorkspaceSwipeSnapshotKey(
            workspace: WorkspaceId("tracking"), display: "synthetic",
            rect: CGRect(x: -20000, y: -20000, width: 200, height: 100)))
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let picture = try XCTUnwrap(context.makeImage())
        let snapshots = WorkspaceSwipeSnapshots(renderer: { _ in .init(image: picture, renderMs: 0) })
        snapshots.cache.insert(picture, for: request.key)
        let preview = WorkspaceSwipePreview(snapshots: snapshots)
        defer { preview.invalidate() }
        let existing = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        for stationary in [false, true] {
            preview.begin(request: request, front: picture, rect: rect, slidesLeft: true)
            let panel = try XCTUnwrap(NSApplication.shared.windows.first {
                !existing.contains(ObjectIdentifier($0)) && $0.isVisible
            })
            let layer = try XCTUnwrap(panel.contentView?.layer?.sublayers?.first)
            preview.update(0.5, timestamp: 10)
            XCTAssertEqual(layer.transform.m41, -100)
            preview.update(0.4, timestamp: 10.05)
            XCTAssertEqual(layer.transform.m41, -80)
            XCTAssertTrue(layer.animationKeys()?.isEmpty ?? true)
            if stationary { preview.update(0.4, timestamp: 10.06) }
            preview.settle(commit: false, timestamp: 10.07)
            let spring = try XCTUnwrap(layer.animation(forKey: "workspaceSwipe") as? CASpringAnimation)
            XCTAssertEqual(spring.toValue as? CGFloat, 0)
            if stationary { XCTAssertEqual(spring.initialVelocity, 0) }
            else { XCTAssertGreaterThan(spring.initialVelocity, 0, "Reversal velocity must survive main-thread delivery timing") }
            preview.cancel()
        }
    }

    func testRepeatedWarmSurfacePreparation() throws {
        let rect = Rect(topLeftX: -20000, topLeftY: -20000, width: 1710, height: 1080)
        let key = WorkspaceSwipeSnapshotKey(workspace: WorkspaceId("benchmark"), display: "synthetic",
                                           rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
        let request = WorkspaceSwipeSnapshotRequest(key: key)
        let context = try XCTUnwrap(CGContext(data: nil, width: 1710, height: 1080,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let picture = try XCTUnwrap(context.makeImage())
        let snapshots = WorkspaceSwipeSnapshots(renderer: { _ in
            WorkspaceSwipeSnapshotResult(image: picture, renderMs: 0)
        })
        let preview = WorkspaceSwipePreview(snapshots: snapshots)
        defer { preview.invalidate() }
        snapshots.cache.insert(picture, for: key)
        for _ in 0..<31 {
            preview.begin(request: request, front: picture, rect: rect, slidesLeft: true)
            XCTAssertTrue(preview.isActive)
            XCTAssertNotNil(preview.timings.last?.panelMs)
            preview.update(0.4)
            preview.cancel()
            XCTAssertFalse(preview.isActive)
        }
        XCTAssertEqual(preview.surfaceCreations, 1, "Ordinary cancellation should reuse the cleared surface")
        let warm = preview.timings.dropFirst().compactMap(\.panelMs).sorted()
        XCTAssertEqual(warm.count, 30)
        print(String(format: "SWIPE_SURFACE_BENCH samples=%d creations=%d panel_p50=%.3fms panel_p95=%.3fms",
            warm.count, preview.surfaceCreations, warm[14], warm[28]))
    }

    func testReusedSurfaceResizesAndInvalidationReleasesIt() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let picture = try XCTUnwrap(context.makeImage())
        let snapshots = WorkspaceSwipeSnapshots(renderer: { _ in
            WorkspaceSwipeSnapshotResult(image: picture, renderMs: 0)
        })
        let preview = WorkspaceSwipePreview(snapshots: snapshots)
        defer { preview.invalidate() }
        let existing = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        for (index, width) in [160.0, 240.0].enumerated() {
            let rect = Rect(topLeftX: -20000, topLeftY: -20000, width: width, height: 90)
            let request = WorkspaceSwipeSnapshotRequest(key: WorkspaceSwipeSnapshotKey(
                workspace: WorkspaceId("target"), display: "synthetic", rect: CGRect(x: -20000, y: -20000, width: width, height: 90)))
            snapshots.cache.insert(picture, for: request.key)
            preview.begin(request: request, front: picture, rect: rect, slidesLeft: index == 0)
            let panels = NSApplication.shared.windows.filter { !existing.contains(ObjectIdentifier($0)) && $0.isVisible }
            XCTAssertEqual(panels.count, 1)
            let panel = try XCTUnwrap(panels.first)
            XCTAssertEqual(panel.frame.size, rect.size)
            for layer in panel.contentView?.layer?.sublayers ?? [] {
                XCTAssertEqual(layer.frame.size, rect.size)
                XCTAssertNotNil(layer.contents)
            }
            XCTAssertEqual(preview.surfaceCreations, 1)
            if index == 0 { preview.cancel() }
            else {
                preview.invalidate()
                XCTAssertNil(panel.contentView)
                XCTAssertFalse(panel.isVisible)
            }
        }
    }

    func testThousandPreviewCyclesReleasePanelsAcrossRepeatedInvalidation() throws {
        let rect = Rect(topLeftX: -20000, topLeftY: -20000, width: 160, height: 90)
        let request = WorkspaceSwipeSnapshotRequest(key: WorkspaceSwipeSnapshotKey(
            workspace: WorkspaceId("lifetime-stress"), display: "synthetic",
            rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)))
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let picture = try XCTUnwrap(context.makeImage())
        for _ in 0..<20 {
            weak var releasedPanel: NSWindow?
            weak var releasedPreview: WorkspaceSwipePreview?
            try autoreleasepool {
                let snapshots = WorkspaceSwipeSnapshots(renderer: { _ in
                    WorkspaceSwipeSnapshotResult(image: picture, renderMs: 0)
                })
                snapshots.cache.insert(picture, for: request.key)
                let preview = WorkspaceSwipePreview(snapshots: snapshots)
                releasedPreview = preview
                defer { preview.invalidate() }
                let existing = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
                for cycle in 0..<50 {
                    preview.begin(request: request, front: picture, rect: rect, slidesLeft: cycle.isMultiple(of: 2))
                    let panel = try XCTUnwrap(NSApplication.shared.windows.first {
                        !existing.contains(ObjectIdentifier($0)) && $0.isVisible
                    })
                    releasedPanel = panel
                    preview.update(0.6)
                    preview.cancel()
                    XCTAssertFalse(panel.isVisible)
                    for layer in panel.contentView?.layer?.sublayers ?? [] {
                        XCTAssertNil(layer.contents)
                        XCTAssertTrue(layer.animationKeys()?.isEmpty ?? true)
                    }
                }
                XCTAssertEqual(preview.surfaceCreations, 1)
                preview.invalidate()
                XCTAssertEqual(snapshots.cache.count, 0)
            }
            XCTAssertNil(releasedPreview)
            XCTAssertNil(releasedPanel, "Invalidation must release each native panel, not accumulate closed panels")
        }
    }

}
