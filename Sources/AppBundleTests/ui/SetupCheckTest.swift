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
        XCTAssertEqual(failing(input), ["accessibility", "other-window-managers"])
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
        XCTAssertEqual(failing(input), [], "Spaces settings do not matter to WinMuxX workspaces")
    }

    func testEitherThreeFingerSwipeSettingWorksAndMacOSRecognitionIsSuggested() {
        var input = healthy
        let item = { setupCheckItems(input).first { $0.id == "three-finger-swipe" } }
        XCTAssertEqual(item()?.ok, true)
        XCTAssertNotNil(item()?.fixURL, "Raw touch works; macOS's recognition is offered")
        input.macThreeFingerHorizontalSwipe = true
        XCTAssertEqual(item()?.ok, true)
        XCTAssertNil(item()?.fixURL, "WinMuxX reads macOS's swipe instead of clashing with it")
        input.workspaceSwipe = false
        XCTAssertNil(item())
    }

    func testEitherSwipeUpSettingWorksAndMacOSRecognitionIsSuggested() {
        var input = healthy
        let item = { setupCheckItems(input).first { $0.id == "three-finger-up" } }
        XCTAssertNil(item())
        input.overviewThreeFingerUp = true
        XCTAssertEqual(item()?.ok, true)
        XCTAssertNotNil(item()?.fixURL)
        input.macThreeFingerVerticalSwipe = true
        XCTAssertEqual(item()?.ok, true)
        XCTAssertNil(item()?.fixURL, "WinMuxX reads macOS's swipe up instead of clashing with Mission Control")
    }
}
