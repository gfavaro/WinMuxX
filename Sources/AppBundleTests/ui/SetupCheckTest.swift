@testable import AppBundle
import XCTest

final class SetupCheckTest: XCTestCase {
    private let healthy = SetupCheckInput(accessibilityGranted: true, otherWindowManagers: [], workspaceSwipe: true,
                                          overviewThreeFingerUp: false, macThreeFingerHorizontalSwipe: false,
                                          macThreeFingerVerticalSwipe: false)

    private func failing(_ input: SetupCheckInput) -> [String] { setupCheckItems(input).filter { !$0.ok }.map(\.id) }

    func testHealthySetupsPass() {
        XCTAssertEqual(failing(healthy), [])
    }

    func testEachProblemIsReportedWithAFix() {
        var input = healthy
        input.accessibilityGranted = false
        input.otherWindowManagers = ["yabai"]
        XCTAssertEqual(failing(input), ["accessibility", "other-window-managers"])
        XCTAssertTrue(setupCheckItems(input).first { $0.id == "other-window-managers" }!.detail.contains("yabai"))
        XCTAssertNotNil(setupCheckItems(input).first { $0.id == "accessibility" }?.fixURL)
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
