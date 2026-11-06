import Common
import XCTest
@testable import AppBundle

final class TestWriteGuardTest: XCTestCase {
    func testOnlyTemporaryPathsAreWritableFromTests() {
        XCTAssertTrue(isTemporaryPath(FileManager.default.temporaryDirectory.appendingPathComponent("native.json")))
        XCTAssertTrue(isTemporaryPath(URL(filePath: "/tmp/x/config.toml")))
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertFalse(isTemporaryPath(home.appendingPathComponent(".config/winmuxx/winmux.toml")), "The user's config")
        XCTAssertFalse(isTemporaryPath(home.appendingPathComponent("Library/Application Support/WinMux-GF/window-state.json")))
        XCTAssertFalse(isTemporaryPath(URL(filePath: "/tmpfoo/x")), "A prefix of a temporary name is not temporary")
    }
}

final class MacAppTeardownTest: XCTestCase {
    /// A thread-guarded value left out of destroy() crashes WinMuxX whenever an app quits.
    func testEveryThreadGuardedValueIsDestroyed() throws {
        let source = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "AppBundle/tree/MacApp.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let guarded = text.matches(of: /let (\w+): ThreadGuardedValue</).map { String($0.1) }
        XCTAssertFalse(guarded.isEmpty)
        for name in guarded {
            XCTAssertTrue(text.contains("\(name).destroy()"), "\(name) is never destroyed in MacApp.destroy()")
        }
    }
}
