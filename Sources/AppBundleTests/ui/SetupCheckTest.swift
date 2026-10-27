@testable import AppBundle
import XCTest

final class SetupCheckTest: XCTestCase {
    private let healthy = SetupCheckInput(backend: .virtual, accessibilityGranted: true, otherWindowManagers: [],
                                          separateSpaces: true, rearrangesSpaces: false, workspaceSwipe: true,
                                          overviewThreeFingerUp: false, macThreeFingerHorizontalSwipe: false,
                                          macThreeFingerVerticalSwipe: false)

    private func failing(_ input: SetupCheckInput) -> [String] { setupCheckItems(input).filter { !$0.ok }.map(\.id) }

    func testHealthySetupsPass() {
        XCTAssertEqual(failing(healthy), [])
        var native = healthy
        native.backend = .native
        XCTAssertEqual(failing(native), [])
    }

    func testEachProblemIsReportedWithAFix() {
        var input = healthy
        input.accessibilityGranted = false
        input.otherWindowManagers = ["yabai"]
        input.macThreeFingerHorizontalSwipe = true
        input.overviewThreeFingerUp = true
        input.macThreeFingerVerticalSwipe = true
        XCTAssertEqual(failing(input), ["accessibility", "other-window-managers", "three-finger-swipe", "three-finger-up"])
        XCTAssertTrue(setupCheckItems(input).first { $0.id == "other-window-managers" }!.detail.contains("yabai"))
        XCTAssertNotNil(setupCheckItems(input).first { $0.id == "accessibility" }?.fixURL)
    }

    func testChecksFollowTheBackend() {
        var input = healthy
        input.backend = .native
        input.separateSpaces = false
        input.rearrangesSpaces = true
        input.macThreeFingerHorizontalSwipe = true // macOS owns desktop swipes in native mode.
        XCTAssertEqual(failing(input), ["separate-spaces", "rearrange-spaces"])
        input.backend = .virtual
        XCTAssertEqual(failing(input), ["three-finger-swipe"], "Spaces settings do not matter to WinMuxX workspaces")
        input.workspaceSwipe = false
        XCTAssertEqual(failing(input), [], "No clash when WinMuxX does not swipe")
    }
}
