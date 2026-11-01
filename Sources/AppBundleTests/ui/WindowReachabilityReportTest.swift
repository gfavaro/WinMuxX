@testable import AppBundle
import XCTest

final class WindowReachabilityReportTest: XCTestCase {
    func testAllReachableIsOneLine() {
        XCTAssertEqual(windowReachabilityReport(trackedCount: 5, unreachable: []),
                       ["  all 5 tracked windows are reachable through Accessibility"])
    }

    func testUnreachableWindowShowsRawAxSourcesAndWindowServerWindows() {
        let diagnosis = UnreachableWindowDiagnosis(
            windowId: 82519, appName: "Safari", workspace: "1",
            windowServerFrame: CGRect(x: 0, y: 38, width: 1710, height: 1074),
            axWindows: [
                AxWindowProbe(source: "AXWindows[0]", windowId: 245086, frame: CGRect(x: 0, y: 0, width: 1710, height: 38),
                              role: "AXWindow", subrole: "AXStandardWindow"),
                AxWindowProbe(source: "AXWindows[1]", idError: "cannotComplete", role: "AXWindow"),
                AxWindowProbe(source: "AXFocusedWindow", failure: "noValue"),
            ],
            appWindowServerWindows: (0..<14).map {
                WindowServerWindowSummary(id: UInt32(100 + $0), frame: CGRect(x: 0, y: 0, width: 10, height: 10), onScreen: $0 == 0)
            })
        let lines = windowReachabilityReport(trackedCount: 5, unreachable: [diagnosis])
        XCTAssertEqual(lines[0], "  window 82519 (Safari, workspace 1) is not reachable through Accessibility: "
            + "WinMux cannot move or park it. WindowServer: 0,38 1710x1074")
        XCTAssertEqual(lines[2], "      AXWindows[0]: id=245086 role=AXWindow subrole=AXStandardWindow frame=0,0 1710x38")
        XCTAssertEqual(lines[3], "      AXWindows[1]: id=none (cannotComplete) role=AXWindow subrole=- frame=unknown")
        XCTAssertEqual(lines[4], "      AXFocusedWindow: unreadable (noValue)")
        XCTAssertTrue(lines[5].hasPrefix("    Safari WindowServer windows (layer 0): 100 on 0,0 10x10; 101 off"))
        XCTAssertTrue(lines[5].hasSuffix("; …"), "Long window lists are capped")
        XCTAssertFalse(lines.joined().contains("title"), "Titles stay out of shared diagnostics")
    }
}
