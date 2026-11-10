@testable import AppBundle
import XCTest

final class WindowTitleCacheTest: WorkspaceTestCase {
    @MainActor
    func testGetCachedWindowTitleReusesFreshValue() async {
        resetCachedWindowTitles()
        let window = StubTitleWindow(id: 42, title: "  Example  ")

        let first = await getCachedWindowTitle(window, maxAge: 60, now: Date(timeIntervalSince1970: 10))
        let second = await getCachedWindowTitle(window, maxAge: 60, now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(first, "Example")
        XCTAssertEqual(second, "Example")
        XCTAssertEqual(window.titleGetCount, 1)
    }

    @MainActor
    func testGetCachedWindowTitleRefreshesExpiredValue() async {
        resetCachedWindowTitles()
        let window = StubTitleWindow(id: 43, title: "First")

        let first = await getCachedWindowTitle(window, maxAge: 1, now: Date(timeIntervalSince1970: 10))
        window.stubTitle = "Second"
        let second = await getCachedWindowTitle(window, maxAge: 1, now: Date(timeIntervalSince1970: 12))

        XCTAssertEqual(first, "First")
        XCTAssertEqual(second, "Second")
        XCTAssertEqual(window.titleGetCount, 2)
    }
}
