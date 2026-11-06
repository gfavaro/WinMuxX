@testable import AppBundle
import XCTest

final class SetupCheckTest: XCTestCase {
    private let healthy = SetupCheckInput(accessibilityGranted: true, otherWindowManagers: [], workspaceSwipe: true,
                                          overviewThreeFingerUp: false, macThreeFingerHorizontalSwipe: true,
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

    func testTheSwipeNeedsMacOSThreeFingerSwipeAndPointsToTheSetting() {
        var input = healthy
        let item = { setupCheckItems(input).first { $0.id == "three-finger-swipe" } }
        XCTAssertEqual(item()?.ok, true)
        XCTAssertNil(item()?.fixURL)
        input.macThreeFingerHorizontalSwipe = false
        XCTAssertEqual(item()?.ok, false)
        XCTAssertNotNil(item()?.fixURL, "Trackpad settings fix it")
        input.workspaceSwipe = false
        XCTAssertNil(item())
    }

    func testTheSwipeUpNeedsMissionControlOnThreeFingers() {
        var input = healthy
        let item = { setupCheckItems(input).first { $0.id == "three-finger-up" } }
        XCTAssertNil(item())
        input.overviewThreeFingerUp = true
        XCTAssertEqual(item()?.ok, false)
        XCTAssertNotNil(item()?.fixURL)
        input.macThreeFingerVerticalSwipe = true
        XCTAssertEqual(item()?.ok, true)
        XCTAssertNil(item()?.fixURL)
    }
}
