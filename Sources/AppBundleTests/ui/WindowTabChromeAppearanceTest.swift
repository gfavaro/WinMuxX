@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class WindowTabChromeAppearanceTest: XCTestCase {
    func testSidebarColorAndTintChangesInvalidateCachedChrome() {
        let previous = config
        defer { config = previous }
        let owner = NSObject()
        let strip = WindowTabStripViewModel(id: ObjectIdentifier(owner), workspaceName: "tabs",
            frame: CGRect(x: 0, y: 0, width: 300, height: 28),
            groupFrame: CGRect(x: 0, y: 0, width: 300, height: 208),
            activeWindowId: 1, activeWindowCornerRadius: 12, tabs: [], occludingFloatingWindowFrames: [])
        let initial = WindowTabGroupChromeContent(strip: strip)
        config.workspaceSidebar.solidChromeCustomColor = "#123456"
        let custom = WindowTabGroupChromeContent(strip: strip)
        XCTAssertNotEqual(initial, custom)
        config.workspaceSidebar.frostedTint = .cyan
        XCTAssertNotEqual(custom, WindowTabGroupChromeContent(strip: strip))
    }
}
