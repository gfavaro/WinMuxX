@testable import AppBundle
import XCTest

/// getSessionWindowTitle is the title accessor for per-session UI model builders: a known
/// window answers from the cache immediately (even past TTL — the stale entry is refreshed in
/// the background), while a first-sight window is fetched inline so its first paint is correct.
final class SessionWindowTitleTest: WorkspaceTestCase {
    @MainActor
    func testBlankRefreshPreservesKnownTitleAndBlankFirstSightReturnsNil() async {
        let start = Date(timeIntervalSince1970: 0)
        let known = StubTitleWindow(id: 64, title: "Document")
        let initial = await getCachedWindowTitle(known, now: start)
        XCTAssertEqual(initial, "Document")
        known.stubTitle = "  \n "
        let refreshed = await getCachedWindowTitle(known, now: start.addingTimeInterval(100))
        XCTAssertEqual(refreshed, "Document")
        XCTAssertEqual(known.titleGetCount, 2)
        let unknown = StubTitleWindow(id: 65, title: "  ")
        let first = await getCachedWindowTitle(unknown, now: start)
        XCTAssertNil(first)
        XCTAssertEqual(unknown.titleGetCount, 1)
    }

    @MainActor
    func testFirstSightFetchesInline() async {
        resetCachedWindowTitles()
        let window = StubTitleWindow(id: 61, title: "Inline")

        let title = await getSessionWindowTitle(window)

        XCTAssertEqual(title, "Inline")
        XCTAssertEqual(window.titleGetCount, 1)
    }

    @MainActor
    func testStaleEntryAnswersImmediatelyWithoutInlineFetch() async {
        resetCachedWindowTitles()
        let window = StubTitleWindow(id: 62, title: "Old")
        _ = await getCachedWindowTitle(window, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(window.titleGetCount, 1)

        window.stubTitle = "New"
        // Way past the 5s TTL: the session accessor must return the stale value synchronously
        // rather than blocking the session on an AX round-trip.
        let title = await getSessionWindowTitle(window, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(title, "Old")
        XCTAssertEqual(window.titleGetCount, 1, "stale entry must not be refreshed inline")

        // The queued background refresh eventually updates the cache.
        for _ in 0 ..< 1000 {
            if cachedWindowTitle(for: window) == "New" { break }
            await Task.yield()
        }
        XCTAssertEqual(cachedWindowTitle(for: window), "New")
        XCTAssertEqual(window.titleGetCount, 2)
    }

    @MainActor
    func testFreshEntryDoesNotScheduleBackgroundRefresh() async {
        resetCachedWindowTitles()
        let window = StubTitleWindow(id: 63, title: "Fresh")
        let now = Date()
        _ = await getCachedWindowTitle(window, now: now)

        let title = await getSessionWindowTitle(window, now: now.addingTimeInterval(1))
        XCTAssertEqual(title, "Fresh")

        for _ in 0 ..< 50 { await Task.yield() }
        XCTAssertEqual(window.titleGetCount, 1, "fresh entries must not be re-fetched")
    }

    @MainActor
    func testReusedWindowIdDoesNotReusePriorOwnerTitle() async {
        resetCachedWindowTitles()
        let old = StubTitleWindow(id: 66, title: "Old window")
        _ = await getCachedWindowTitle(old)
        old.unbindFromParent()
        let replacement = StubTitleWindow(id: 66, title: "Replacement")

        let title = await getSessionWindowTitle(replacement)

        XCTAssertEqual(title, "Replacement")
        XCTAssertEqual(replacement.titleGetCount, 1)
    }
}
