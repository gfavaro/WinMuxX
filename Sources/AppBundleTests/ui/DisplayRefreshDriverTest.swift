@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class DisplayRefreshDriverTest: XCTestCase {
    /// The driver follows one display; when displays change it binds again, and frames go on.
    func testFramesContinueAfterADisplayChange() async throws {
        _ = NSApplication.shared
        let owner = NSObject()
        var frames = 0
        DisplayRefreshDriver.shared.add(owner: owner) { _ in frames += 1 }
        defer { DisplayRefreshDriver.shared.remove(owner: owner) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(frames, 0, "Frames arrive")
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let afterChange = frames
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(frames, afterChange, "and keep arriving after displays change")
    }
}
