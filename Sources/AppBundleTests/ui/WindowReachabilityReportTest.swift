@testable import AppBundle
import XCTest

final class WindowReachabilityReportTest: XCTestCase {
    func testAllReachableIsOneLine() {
        XCTAssertEqual(windowReachabilityReport(trackedCount: 5, findings: [], details: []),
                       ["  all 5 tracked windows are reachable through Accessibility"])
    }

    func testEachFindingSaysWhyAndAppDetailsAppearOnce() {
        let frame = CGRect(x: 0, y: 38, width: 1710, height: 1074)
        let findings = [
            WindowReachabilityFinding(windowId: 82519, appName: "Safari", workspace: "1", windowServerFrame: frame,
                                      reachability: .appRetired, liveAppRegistered: true),
            WindowReachabilityFinding(windowId: 82520, appName: "Safari", workspace: "2", windowServerFrame: nil, reachability: .unreachable),
            WindowReachabilityFinding(windowId: 9, appName: "Busy", workspace: nil, windowServerFrame: nil,
                                      reachability: .unknown("the app did not answer")),
        ]
        let details = [AppReachabilityDetail(appName: "Safari",
            axWindows: [
                AxWindowProbe(source: "AXWindows[0]", windowId: 245086, frame: CGRect(x: 0, y: 0, width: 1710, height: 38),
                              role: "AXWindow", subrole: "AXStandardWindow"),
                AxWindowProbe(source: "AXWindows[1]", idError: "cannotComplete", role: "AXWindow"),
                AxWindowProbe(source: "AXFocusedWindow", failure: "noValue"),
            ],
            windowServerWindows: (0..<14).map { WindowServerWindowSummary(id: UInt32(100 + $0), frame: CGRect(x: 0, y: 0, width: 10, height: 10), onScreen: $0 == 0) })]
        let lines = windowReachabilityReport(trackedCount: 6, findings: findings, details: details)
        XCTAssertEqual(lines[0], "  window 82519 (Safari, workspace 1) belongs to a destroyed app object while Safari still runs "
            + "(live object registered: yes), so WinMux cannot move or park it. WindowServer: 0,38 1710x1074")
        XCTAssertEqual(lines[1], "  window 82520 (Safari, workspace 2) has no Accessibility element, so WinMux cannot move or park it. WindowServer: unknown")
        XCTAssertEqual(lines[2], "  window 9 (Busy, workspace none) could not be checked: the app did not answer. WindowServer: unknown")
        XCTAssertEqual(lines.filter { $0.contains("Safari Accessibility windows") }.count, 1, "Each app is probed once")
        XCTAssertEqual(lines[4], "    AXWindows[0]: id=245086 role=AXWindow subrole=AXStandardWindow frame=0,0 1710x38")
        XCTAssertEqual(lines[5], "    AXWindows[1]: id=none (cannotComplete) role=AXWindow subrole=- frame=unknown")
        XCTAssertEqual(lines[6], "    AXFocusedWindow: unreadable (noValue)")
        XCTAssertTrue(lines[7].hasPrefix("  Safari WindowServer windows (layer 0): 100 on 0,0 10x10; 101 off"))
        XCTAssertTrue(lines[7].hasSuffix("; …"), "Long window lists are capped")
    }

    func testAnAppThatWasNotProbedIsNotReportedAsHavingNoWindows() {
        let finding = WindowReachabilityFinding(windowId: 1, appName: "Slow", workspace: "1", windowServerFrame: nil,
                                                reachability: .unknown("the app did not answer"))
        let lines = windowReachabilityReport(trackedCount: 1, findings: [finding],
            details: [AppReachabilityDetail(appName: "Slow", axWindows: nil, windowServerWindows: [])])
        XCTAssertEqual(lines[1], "  Slow Accessibility windows: not probed, the app did not answer")
        XCTAssertFalse(lines.contains("    none"))
    }

    func testUnknownIsNeverReportedAsAllReachable() {
        let finding = WindowReachabilityFinding(windowId: 1, appName: "App", workspace: "1", windowServerFrame: nil,
                                                reachability: .unknown("the check was interrupted"))
        let lines = windowReachabilityReport(trackedCount: 1, findings: [finding], details: [])
        XCTAssertFalse(lines.joined().contains("all 1 tracked windows are reachable"))
    }
}
