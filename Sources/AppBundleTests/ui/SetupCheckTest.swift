@testable import AppBundle
import XCTest

final class SetupCheckTest: XCTestCase {
    private let healthy = SetupCheckInput(accessibilityGranted: true, otherWindowManagers: [], workspaceSwipe: true,
                                          macThreeFingerVerticalSwipe: true)

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

    func testTheSwipeNeedsMissionControlOnThreeFingersAndPointsToTheSetting() {
        var input = healthy
        let item = { setupCheckItems(input).first { $0.id == "three-finger-swipe" } }
        XCTAssertEqual(item()?.ok, true)
        XCTAssertNil(item()?.fixURL)
        input.macThreeFingerVerticalSwipe = false
        XCTAssertEqual(item()?.ok, false)
        XCTAssertNotNil(item()?.fixURL, "Trackpad settings fix it")
        input.workspaceSwipe = false
        XCTAssertNil(item())
    }
}
