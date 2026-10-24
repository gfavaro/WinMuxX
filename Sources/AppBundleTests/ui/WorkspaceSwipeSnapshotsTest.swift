@testable import AppBundle
import AppKit
import Common
import XCTest

private actor ControlledSwipeRenderer {
    private var continuations: [WorkspaceId: CheckedContinuation<WorkspaceSwipeSnapshotResult, any Error>] = [:]
    private(set) var requests: [WorkspaceId] = []
    let started: @Sendable (WorkspaceId) -> Void

    init(started: @escaping @Sendable (WorkspaceId) -> Void) { self.started = started }

    func render(_ request: WorkspaceSwipeSnapshotRequest) async throws -> WorkspaceSwipeSnapshotResult {
        requests.append(request.key.workspace)
        return try await withCheckedThrowingContinuation {
            continuations[request.key.workspace] = $0
            started(request.key.workspace)
        }
    }

    func finish(_ id: WorkspaceId, image: CGImage) {
        continuations.removeValue(forKey: id)?.resume(returning: WorkspaceSwipeSnapshotResult(image: image, renderMs: 120))
    }

    func cancelAll() {
        let waiting = Array(continuations.values)
        continuations.removeAll()
        for continuation in waiting { continuation.resume(throwing: CancellationError()) }
    }

    func fail(_ id: WorkspaceId) {
        continuations.removeValue(forKey: id)?.resume(throwing: CocoaError(.fileReadUnknown))
    }
}

@MainActor
final class WorkspaceSwipeSnapshotsTest: XCTestCase {
    private let rect = Rect(topLeftX: -20000, topLeftY: -20000, width: 160, height: 90)
    private func request(_ name: String = "target", display: String = "main", width: Double = 160) -> WorkspaceSwipeSnapshotRequest {
        WorkspaceSwipeSnapshotRequest(key: WorkspaceSwipeSnapshotKey(workspace: WorkspaceId(name), display: display,
            rect: CGRect(x: -20000, y: -20000, width: width, height: 90)))
    }
    private func controlledRenderer(started: @escaping @Sendable (WorkspaceId) -> Void) -> ControlledSwipeRenderer {
        let gate = ControlledSwipeRenderer(started: started)
        addTeardownBlock { await gate.cancelAll() }
        return gate
    }
    private func image(width: Int = 16, height: Int = 16) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    func testCacheHonorsLruByteAndCountLimitsAndGeometryIdentity() throws {
        let picture = try image()
        let cost = picture.bytesPerRow * picture.height
        var cache = WorkspaceSwipeSnapshotCache(maxImages: 2, maxBytes: cost * 2)
        cache.insert(picture, for: request("a").key)
        cache.insert(picture, for: request("b").key)
        XCTAssertNotNil(cache.image(for: request("a").key))
        cache.insert(picture, for: request("c").key)
        XCTAssertNil(cache.image(for: request("b").key))
        XCTAssertNotNil(cache.image(for: request("a").key))
        XCTAssertNil(cache.image(for: request("a", display: "external").key))
        XCTAssertNil(cache.image(for: request("a", width: 200).key))
        XCTAssertEqual(cache.bytes, cost * 2)
        cache.insert(picture, for: request("a").key)
        XCTAssertEqual(cache.bytes, cost * 2, "Replacing an entry must not count its storage twice")
        let oversized = try image(width: 256, height: 256)
        cache.insert(oversized, for: request("large").key)
        XCTAssertNil(cache.image(for: request("large").key))
        XCTAssertLessThanOrEqual(cache.bytes, cache.maxBytes)
        cache.clear()
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.bytes, 0)

        var byteLimited = WorkspaceSwipeSnapshotCache(maxImages: 4, maxBytes: cost)
        byteLimited.insert(picture, for: request("a").key)
        byteLimited.insert(picture, for: request("b").key)
        XCTAssertEqual(byteLimited.count, 1)
        XCTAssertNil(byteLimited.image(for: request("a").key))
    }

    func testOnlyNewestPendingRenderRunsAndCancelledWorkCannotPopulateCache() async throws {
        let startedA = expectation(description: "a started")
        let startedC = expectation(description: "c started")
        let finished = expectation(description: "c delivered")
        let gate = controlledRenderer {
            if $0 == WorkspaceId("a") { startedA.fulfill() }
            if $0 == WorkspaceId("c") { startedC.fulfill() }
        }
        let snapshots = WorkspaceSwipeSnapshots(renderer: { try await gate.render($0) })
        defer { snapshots.invalidate() }
        snapshots.request(request("a")) { _ in XCTFail("Obsolete a delivered") }
        await fulfillment(of: [startedA], timeout: 2)
        snapshots.request(request("b")) { _ in XCTFail("Superseded b delivered") }
        snapshots.request(request("c")) { result in
            if case .failure(let error) = result { XCTFail("Unexpected render failure: \(error)") }
            finished.fulfill()
        }
        let picture = try image()
        await gate.finish(WorkspaceId("a"), image: picture)
        await fulfillment(of: [startedC], timeout: 2)
        let requests = await gate.requests
        XCTAssertEqual(requests, [WorkspaceId("a"), WorkspaceId("c")])
        XCTAssertNil(snapshots.cache.image(for: request("a").key))
        await gate.finish(WorkspaceId("c"), image: picture)
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertNotNil(snapshots.cache.image(for: request("c").key))
    }

    func testColdReleaseBeforeImageReadinessCannotOpenLateOverlay() async throws {
        for commit in [false, true] {
            let started = expectation(description: "cold render started")
            let drained = expectation(description: "next render delivered")
            let nextStarted = expectation(description: "next render started")
            let gate = controlledRenderer {
                if $0 == WorkspaceId("target") { started.fulfill() } else { nextStarted.fulfill() }
            }
            let snapshots = WorkspaceSwipeSnapshots(renderer: { try await gate.render($0) })
            let preview = WorkspaceSwipePreview(snapshots: snapshots)
            defer { preview.invalidate() }
            let picture = try image()
            preview.begin(request: request(), front: picture, rect: rect, slidesLeft: true)
            preview.update(0.7)
            await fulfillment(of: [started], timeout: 2)
            XCTAssertTrue(preview.isActive, "Preparation must be cancellable before a panel exists")
            XCTAssertNil(preview.timings.last?.submissionMs)
            preview.settle(commit: commit)
            XCTAssertFalse(preview.isActive)
            snapshots.request(request("drain")) { _ in drained.fulfill() }
            await gate.finish(WorkspaceId("target"), image: picture)
            await fulfillment(of: [nextStarted], timeout: 2)
            await gate.finish(WorkspaceId("drain"), image: picture)
            await fulfillment(of: [drained], timeout: 2)
            XCTAssertFalse(preview.isActive)
            XCTAssertNil(preview.timings.last?.submissionMs)
        }
    }

    func testWarmPreviewIsSubmittedBeforeFreshRendererCanComplete() async throws {
        let started = expectation(description: "refresh started")
        let gate = controlledRenderer { _ in started.fulfill() }
        let snapshots = WorkspaceSwipeSnapshots(renderer: { try await gate.render($0) })
        let picture = try image()
        snapshots.cache.insert(picture, for: request().key)
        let preview = WorkspaceSwipePreview(snapshots: snapshots)
        defer { preview.invalidate() }
        preview.begin(request: request(), front: picture, rect: rect, slidesLeft: true)
        XCTAssertTrue(preview.timings.last?.cacheHit == true)
        XCTAssertNotNil(preview.timings.last?.submissionMs, "Warm start must not await rendering")
        await fulfillment(of: [started], timeout: 2)
        preview.update(0.4)
        preview.settle(commit: true)
        await gate.finish(WorkspaceId("target"), image: picture)
        XCTAssertTrue(preview.isSettling)
        preview.revealWorkspace()
    }

    func testFailedRenderIsNotCachedAndInvalidationDropsImages() async throws {
        let started = expectation(description: "render started")
        let failed = expectation(description: "failure observed")
        let gate = controlledRenderer { _ in started.fulfill() }
        let snapshots = WorkspaceSwipeSnapshots(renderer: { try await gate.render($0) })
        snapshots.request(request()) { result in
            guard case .failure = result else { return XCTFail("Expected failure") }
            failed.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        await gate.fail(WorkspaceId("target"))
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertNil(snapshots.cache.image(for: request().key))
        snapshots.cache.insert(try image(), for: request().key)
        snapshots.invalidate()
        XCTAssertEqual(snapshots.cache.count, 0)
    }

    func testFreshWarmImageReplacesCacheWithoutResubmittingTheOverlay() async throws {
        let started = expectation(description: "refresh started")
        let delivered = expectation(description: "refresh delivered")
        let gate = controlledRenderer { _ in started.fulfill() }
        let snapshots = WorkspaceSwipeSnapshots(renderer: { try await gate.render($0) })
        let oldImage = try image()
        let freshImage = try image(width: 32)
        snapshots.cache.insert(oldImage, for: request().key)
        let preview = WorkspaceSwipePreview(snapshots: snapshots)
        defer { preview.invalidate() }
        preview.begin(request: request(), front: oldImage, rect: rect, slidesLeft: false) {
            delivered.fulfill()
            return true
        }
        let firstSubmission = preview.timings.last?.submissionMs
        preview.update(0.6)
        await fulfillment(of: [started], timeout: 2)
        await gate.finish(WorkspaceId("target"), image: freshImage)
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertTrue(preview.isActive)
        XCTAssertFalse(preview.isSettling)
        XCTAssertEqual(preview.timings.last?.submissionMs, firstSubmission)
        XCTAssertEqual(preview.timings.last?.workerMs, 120)
        XCTAssertTrue(snapshots.cache.image(for: request().key) === freshImage)
    }

    func testColdFailureFallsBackAndWarmFailureKeepsItsPreview() async throws {
        for warm in [false, true] {
            let started = expectation(description: "render started")
            let delivered = expectation(description: "failure delivered")
            let gate = controlledRenderer { _ in started.fulfill() }
            let snapshots = WorkspaceSwipeSnapshots(renderer: { try await gate.render($0) })
            let picture = try image()
            if warm { snapshots.cache.insert(picture, for: request().key) }
            let preview = WorkspaceSwipePreview(snapshots: snapshots)
            defer { preview.invalidate() }
            preview.begin(request: request(), front: picture, rect: rect, slidesLeft: true) {
                delivered.fulfill()
                return true
            }
            await fulfillment(of: [started], timeout: 2)
            await gate.fail(WorkspaceId("target"))
            await fulfillment(of: [delivered], timeout: 2)
            XCTAssertEqual(preview.isActive, warm)
            XCTAssertEqual(preview.timings.last?.submissionMs != nil, warm)
        }
    }

    func testChangedDestinationOrRevokedPermissionDropsLateImageAndCache() async throws {
        let started = expectation(description: "render started")
        let delivered = expectation(description: "validation performed")
        let gate = controlledRenderer { _ in started.fulfill() }
        let snapshots = WorkspaceSwipeSnapshots(renderer: { try await gate.render($0) })
        let preview = WorkspaceSwipePreview(snapshots: snapshots)
        defer { preview.invalidate() }
        let picture = try image()
        var valid = true
        preview.begin(request: request(), front: picture, rect: rect, slidesLeft: true) {
            delivered.fulfill()
            return valid
        }
        await fulfillment(of: [started], timeout: 2)
        valid = false
        await gate.finish(WorkspaceId("target"), image: picture)
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertFalse(preview.isActive)
        XCTAssertEqual(snapshots.cache.count, 0)
        XCTAssertNil(preview.timings.last?.submissionMs)
    }

    func testOutgoingCaptureIsCancellableBeforeWarmPreviewAndPreservesLatestProgress() async throws {
        let captured = expectation(description: "capture started")
        let refreshed = expectation(description: "incoming refresh started")
        let gate = controlledRenderer {
            if $0 == WorkspaceId("source") { captured.fulfill() } else { refreshed.fulfill() }
        }
        let snapshots = WorkspaceSwipeSnapshots(renderer: { try await gate.render($0) })
        let picture = try image()
        snapshots.cache.insert(picture, for: request().key)
        let preview = WorkspaceSwipePreview(snapshots: snapshots)
        defer { preview.invalidate() }
        let capture = WorkspaceSwipeSnapshotRequest(screenKey: request("source").key,
            rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
        let existing = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        preview.begin(request: request(), capture: capture, rect: rect, slidesLeft: true)
        XCTAssertTrue(preview.isActive)
        XCTAssertNil(preview.timings.last?.submissionMs)
        await fulfillment(of: [captured], timeout: 2)
        preview.update(0.6)
        await gate.finish(WorkspaceId("source"), image: picture)
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertNotNil(preview.timings.last?.submissionMs, "Warm incoming image need not wait for fresh composition")
        XCTAssertEqual(preview.timings.last?.captureMs, 120)
        let panel = try XCTUnwrap(NSApplication.shared.windows.first { !existing.contains(ObjectIdentifier($0)) && $0.isVisible })
        let layer = try XCTUnwrap(panel.contentView?.layer?.sublayers?.first)
        XCTAssertEqual(layer.transform.m41, -rect.width * WorkspaceSwipePreviewGeometry.trackingProgress(0.6), accuracy: 0.001)
        preview.cancel()
        XCTAssertFalse(panel.isVisible)
        for layer in panel.contentView?.layer?.sublayers ?? [] {
            XCTAssertNil(layer.contents, "Hidden reusable panels must release old workspace pixels")
            XCTAssertTrue(layer.animationKeys()?.isEmpty ?? true)
            XCTAssertEqual(layer.transform.m41, 0)
        }
        await gate.finish(WorkspaceId("target"), image: picture)
    }

    func testReleaseDuringOutgoingCaptureCannotOpenLateOverlayOrCacheIt() async throws {
        for commit in [true, false] {
            let captured = expectation(description: "capture started")
            let drainStarted = expectation(description: "drain started")
            let drained = expectation(description: "worker drained")
            let gate = controlledRenderer {
                if $0 == WorkspaceId("source") { captured.fulfill() } else { drainStarted.fulfill() }
            }
            let snapshots = WorkspaceSwipeSnapshots(renderer: { try await gate.render($0) })
            let picture = try image()
            snapshots.cache.insert(picture, for: request().key)
            let preview = WorkspaceSwipePreview(snapshots: snapshots)
            defer { preview.invalidate() }
            let capture = WorkspaceSwipeSnapshotRequest(screenKey: request("source").key, rect: .zero)
            preview.begin(request: request(), capture: capture, rect: rect, slidesLeft: true)
            await fulfillment(of: [captured], timeout: 2)
            preview.settle(commit: commit)
            snapshots.request(request("drain")) { _ in drained.fulfill() }
            await gate.finish(WorkspaceId("source"), image: picture)
            await fulfillment(of: [drainStarted], timeout: 2)
            await gate.finish(WorkspaceId("drain"), image: picture)
            await fulfillment(of: [drained], timeout: 2)
            XCTAssertFalse(preview.isActive)
            XCTAssertEqual(preview.surfaceCreations, 0)
            XCTAssertNil(preview.timings.last?.submissionMs)
            XCTAssertNil(snapshots.cache.image(for: capture.key))
        }
    }

    func testFailedOrInvalidOutgoingCaptureNeverShowsCachedIncomingPixels() async throws {
        for invalid in [false, true] {
            let captured = expectation(description: "capture started")
            let validated = expectation(description: "capture validated")
            let gate = controlledRenderer { _ in captured.fulfill() }
            let snapshots = WorkspaceSwipeSnapshots(renderer: { try await gate.render($0) })
            let picture = try image()
            snapshots.cache.insert(picture, for: request().key)
            let preview = WorkspaceSwipePreview(snapshots: snapshots)
            defer { preview.invalidate() }
            let capture = WorkspaceSwipeSnapshotRequest(screenKey: request("source").key, rect: .zero)
            preview.begin(request: request(), capture: capture, rect: rect, slidesLeft: true) {
                validated.fulfill()
                return !invalid
            }
            await fulfillment(of: [captured], timeout: 2)
            if invalid { await gate.finish(WorkspaceId("source"), image: picture) }
            else { await gate.fail(WorkspaceId("source")) }
            await fulfillment(of: [validated], timeout: 2)
            XCTAssertFalse(preview.isActive)
            XCTAssertEqual(preview.surfaceCreations, 0)
            if invalid { XCTAssertEqual(snapshots.cache.count, 0) }
        }
    }

    func testLiveRendererCanComposeAnEmptyWorkspaceWithoutDesktopCapture() async throws {
        let completed = expectation(description: "offscreen composition")
        let snapshots = WorkspaceSwipeSnapshots()
        defer { snapshots.invalidate() }
        snapshots.request(request()) { result in
            switch result {
                case .success(let snapshot):
                    XCTAssertFalse(snapshot.renderedOnMainThread, "Native rendering must leave the input/UI thread")
                    XCTAssertEqual(snapshot.image.width, 160)
                    XCTAssertEqual(snapshot.image.height, 90)
                case .failure(let error): XCTFail("\(error)")
            }
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 2)
    }
}
