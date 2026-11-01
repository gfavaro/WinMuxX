@testable import AppBundle
import AppKit
import XCTest

private final class App: AxUiElementMock {
    var enhanced: Bool?
    var reads = 0
    var writes: [Bool] = []
    init(enhanced: Bool?) { self.enhanced = enhanced }
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        guard attr.key == Ax.enhancedUserInterfaceAttr.key else { return nil }
        reads += 1
        return enhanced as? Attr.T
    }
    func containingWindowId() -> CGWindowID? { nil }
    func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool {
        if let value = value as? Bool { writes.append(value); enhanced = value }
        return true
    }
}

final class EnhancedUserInterfaceTest: XCTestCase {
    func testEnabledInterfaceIsSwitchedOffForTheWriteAndRestored() throws {
        let app = App(enhanced: true)
        var stateDuringWrite: Bool?
        try disableAnimations(app: app, RunLoopJob(), assistiveTechnologyActive: false) { stateDuringWrite = app.enhanced }
        XCTAssertEqual(stateDuringWrite, false)
        XCTAssertEqual(app.writes, [false, true])
    }

    func testAssistiveTechnologyKeepsTheInterfaceUntouched() throws {
        let app = App(enhanced: true)
        var ran = false
        try disableAnimations(app: app, RunLoopJob(), assistiveTechnologyActive: true) { ran = true }
        XCTAssertTrue(ran)
        XCTAssertEqual(app.reads, 0, "VoiceOver and Switch Control users keep the interface; it is not even read")
        XCTAssertTrue(app.writes.isEmpty)
    }

    func testDisabledInterfaceIsNotWritten() throws {
        let app = App(enhanced: false)
        try disableAnimations(app: app, RunLoopJob(), assistiveTechnologyActive: false) {}
        XCTAssertTrue(app.writes.isEmpty)
    }
}
