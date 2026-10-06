@testable import AppBundle
import AppKit
import XCTest

final class AxWindowDiscoveryTest: XCTestCase {
    private final class Element: AxUiElementMock {
        let id: UInt32?
        var listed: [WindowIdAndAxUiElementMock]?
        var main: WindowIdAndAxUiElementMock?
        var focused: WindowIdAndAxUiElementMock?
        var reads: [String] = []

        init(_ id: UInt32? = nil) { self.id = id }
        var window: WindowIdAndAxUiElementMock { (id!, self) }
        func containingWindowId() -> CGWindowID? { id }
        func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
            reads.append(attr.key)
            switch attr.key {
                case kAXWindowsAttribute: return listed as? Attr.T
                case kAXMainWindowAttribute: return main as? Attr.T
                case kAXFocusedWindowAttribute: return focused as? Attr.T
                default: return nil
            }
        }
    }

    func testEmptyElectronListFindsMainWindowWithoutRequiringFocus() {
        let app = Element()
        let main = Element(101)
        app.listed = []
        app.main = main.window
        XCTAssertEqual((app.discoverAxWindows() ?? []).map(\.windowId), [101])
        XCTAssertTrue(app.findAxWindow(windowId: 101)?.ax as? Element === main)
    }

    func testUnsupportedWindowListFallsBackToFocusedWindow() {
        let app = Element()
        app.focused = Element(102).window
        XCTAssertEqual((app.discoverAxWindows() ?? []).map(\.windowId), [102])
        XCTAssertEqual(app.findAxWindow(windowId: 102)?.windowId, 102)
    }

    func testPartialListAddsMissingMainAndFocusedWindows() {
        let app = Element()
        app.listed = [Element(101).window]
        app.main = Element(102).window
        app.focused = Element(103).window
        XCTAssertEqual((app.discoverAxWindows() ?? []).map(\.windowId), [101, 102, 103])
    }

    func testDeduplicationPrefersListedElementAndMainOverFocused() {
        let app = Element()
        let listed = Element(101)
        app.listed = [listed.window]
        app.main = Element(101).window
        app.focused = Element(101).window
        let windows = app.discoverAxWindows() ?? []
        XCTAssertEqual(windows.count, 1)
        XCTAssertTrue(windows.first?.ax as? Element === listed)
        app.listed = []
        XCTAssertTrue(app.discoverAxWindows()?.first?.ax as? Element === app.main?.ax as? Element)
    }

    func testMatchingListDoesNotQueryFallbackAttributes() {
        let app = Element()
        app.listed = [Element(101).window]
        XCTAssertEqual(app.findAxWindow(windowId: 101)?.windowId, 101)
        XCTAssertEqual(app.reads, [kAXWindowsAttribute])
    }

    func testFallbackNeverTargetsAnotherWindowIdOrInventsAWindow() {
        let app = Element()
        app.main = Element(101).window
        app.focused = Element(102).window
        XCTAssertNil(app.findAxWindow(windowId: 999))
        let empty = Element()
        XCTAssertNil(empty.discoverAxWindows())
        empty.listed = []
        XCTAssertEqual(empty.discoverAxWindows()?.count, 0)
        empty.main = Element(0).window
        XCTAssertNil(empty.findAxWindow(windowId: 0))
        XCTAssertEqual(empty.discoverAxWindows()?.count, 0)
        XCTAssertNil(empty.findAxWindow(windowId: 101))
    }
}
