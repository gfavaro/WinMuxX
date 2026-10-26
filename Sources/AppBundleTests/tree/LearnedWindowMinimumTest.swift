@testable import AppBundle
import AppKit
import XCTest

final class LearnedWindowMinimumTest: XCTestCase {
    @MainActor
    func testPerAppForgetInvalidatesFrozenEvidenceAndPersistsGeneration() throws {
        let suite = "LearnedWindowMinimumTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistedAppMinimums(defaults: defaults)
        store.remember(CGSize(width: 800, height: 600), for: "com.example.one")
        store.remember(CGSize(width: 900, height: 700), for: "com.example.two")
        let stale = store.evidenceGeneration(for: "com.example.one")
        store.forget("com.example.one")
        XCTAssertFalse(store.acceptsEvidence(stale, for: "com.example.one", savedBundleId: "com.example.one"))
        XCTAssertNil(store.size(for: "com.example.one"))
        XCTAssertEqual(store.size(for: "com.example.two"), CGSize(width: 900, height: 700))

        let restored = PersistedAppMinimums(defaults: defaults)
        XCTAssertEqual(restored.evidenceGeneration(for: "com.example.one").app, 1)
        XCTAssertFalse(restored.acceptsEvidence(stale, for: "com.example.one", savedBundleId: "com.example.one"))
    }

    @MainActor
    func testGlobalForgetInvalidatesAllOldEvidenceAndSnapshotShowsUnknownAxes() throws {
        let suite = "LearnedWindowMinimumTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistedAppMinimums(defaults: defaults)
        store.remember(CGSize(width: 720, height: 0), for: "com.example.one")
        let evidence = store.evidenceGeneration(for: "com.example.one")
        XCTAssertEqual(store.snapshot.first?.unknownAxes, ["height"])
        store.forgetAll()
        XCTAssertFalse(store.acceptsEvidence(evidence, for: "com.example.one", savedBundleId: "com.example.one"))
        XCTAssertTrue(store.snapshot.isEmpty)
        XCTAssertEqual(PersistedAppMinimums(defaults: defaults).evidenceGeneration(for: "com.example.one").global, 1)
    }

    func testFullscreenMinimizedAndIntermediateAnimationFramesAreNotEvidence() {
        XCTAssertTrue(shouldLearnWindowMinimum(nativeFullscreen: false, nativeMinimized: false, animating: false))
        XCTAssertFalse(shouldLearnWindowMinimum(nativeFullscreen: true, nativeMinimized: false, animating: false))
        XCTAssertFalse(shouldLearnWindowMinimum(nativeFullscreen: false, nativeMinimized: true, animating: false))
        XCTAssertFalse(shouldLearnWindowMinimum(nativeFullscreen: false, nativeMinimized: false, animating: true))
    }

    func testConfirmedRefusalLearnsEachAxisIndependently() {
        var minimum = LearnedWindowMinimum()
        minimum.observe(requested: CGSize(width: 200, height: 300),
                        first: CGSize(width: 400, height: 300),
                        confirmed: CGSize(width: 400, height: 300))
        XCTAssertTrue(minimum.isEmpty)
        minimum.observe(requested: CGSize(width: 220, height: 300),
                        first: CGSize(width: 400, height: 300),
                        confirmed: CGSize(width: 400, height: 300))
        XCTAssertEqual(minimum.size, CGSize(width: 400, height: 0))
    }

    func testDelayedResizeAndCellRoundingDoNotBecomeMinima() {
        var minimum = LearnedWindowMinimum()
        minimum.observe(requested: CGSize(width: 200, height: 200),
                        first: CGSize(width: 400, height: 400),
                        confirmed: CGSize(width: 200, height: 200))
        minimum.observe(requested: CGSize(width: 200, height: 200),
                        first: CGSize(width: 210, height: 218),
                        confirmed: CGSize(width: 210, height: 218))
        XCTAssertTrue(minimum.isEmpty)
    }

    func testSuccessfulSmallerResizeInvalidatesEarlierEvidence() {
        var minimum = LearnedWindowMinimum()
        minimum.observe(requested: CGSize(width: 200, height: 200),
                        first: CGSize(width: 400, height: 400),
                        confirmed: CGSize(width: 400, height: 400))
        minimum.observe(requested: CGSize(width: 220, height: 220),
                        first: CGSize(width: 400, height: 400),
                        confirmed: CGSize(width: 400, height: 400))
        minimum.observe(requested: CGSize(width: 300, height: 300),
                        first: CGSize(width: 300, height: 300),
                        confirmed: CGSize(width: 300, height: 300))
        XCTAssertTrue(minimum.isEmpty)
    }

    func testInvalidGeometryIsIgnoredAndWindowsDoNotShareLimits() {
        var first = LearnedWindowMinimum()
        let second = LearnedWindowMinimum()
        first.observe(requested: CGSize(width: 200, height: 200),
                      first: CGSize(width: 400, height: 400),
                      confirmed: CGSize(width: 400, height: 400))
        first.observe(requested: CGSize(width: 220, height: 220),
                      first: CGSize(width: 400, height: 400),
                      confirmed: CGSize(width: 400, height: 400))
        XCTAssertTrue(second.isEmpty)
        first.observe(requested: CGSize(width: CGFloat.nan, height: 200),
                      first: CGSize(width: 900, height: 900),
                      confirmed: CGSize(width: 900, height: 900))
        XCTAssertEqual(first.size, CGSize(width: 400, height: 400))
    }
    func testRepeatingSameRefusalNeverConfirmsMinimum() {
        var minimum = LearnedWindowMinimum()
        for _ in 0..<30 {
            minimum.observe(requested: CGSize(width: 200, height: 200),
                            first: CGSize(width: 400, height: 400),
                            confirmed: CGSize(width: 400, height: 400))
        }
        XCTAssertTrue(minimum.isEmpty)
        minimum.observe(requested: CGSize(width: 240, height: 240),
                        first: CGSize(width: 400, height: 400),
                        confirmed: CGSize(width: 400, height: 400))
        XCTAssertEqual(minimum.size, CGSize(width: 400, height: 400))
    }

    func testGridRoundingFollowsRequestInsteadOfTeachingAnAppWideFloor() {
        var minimum = LearnedWindowMinimum()
        for requested in [200, 280, 360, 200, 280] {
            minimum.observe(requested: CGSize(width: requested, height: 200),
                            first: CGSize(width: requested + 40, height: 200),
                            confirmed: CGSize(width: requested + 40, height: 200))
        }
        XCTAssertTrue(minimum.isEmpty)
    }

}
