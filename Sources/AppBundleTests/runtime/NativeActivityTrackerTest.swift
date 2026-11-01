import Common
import XCTest
@testable import AppBundle
@testable import NativeSpaces

@MainActor
final class NativeActivityTrackerTest: XCTestCase {
    private func displays(active: String) -> [NativeSpaceDisplay] {
        [NativeSpaceDisplay(identifier: "display-a", activeSpaceID: active, spaces: [
            NativeSpace(id: "1", uuid: "a", type: 0), NativeSpace(id: "9", uuid: "full", type: 4),
            NativeSpace(id: "2", uuid: "b", type: 0),
        ])]
    }

    func testHooksFireOnceWithDesktopNumbersAndHistorySkipsFullscreen() {
        setUpWorkspacesForTests()
        config.afterStartupCommand = parseConfig("after-startup-command = ['balance-sizes']").config.afterStartupCommand
        config.onFocusChanged = parseConfig("on-focus-changed = ['balance-sizes']").config.onFocusChanged
        let tracker = NativeActivityTracker()
        var hooks: [String] = []
        var workspaceChanges: [String] = []
        tracker.runHooks = { commands, env in if !commands.isEmpty { hooks.append(env.extraEnvironment["WINMUX_EVENT"] ?? "") } }
        tracker.execWorkspaceChange = { new, previous in workspaceChanges.append("\(previous)->\(new)") }

        tracker.observe(displays(active: "1"), focusedDisplay: "display-a", focusedWindow: 10)
        tracker.observe(displays(active: "1"), focusedDisplay: "display-a", focusedWindow: 10)
        XCTAssertEqual(hooks, ["startup"], "Startup runs once; unchanged state fires nothing")

        tracker.observe(displays(active: "9"), focusedDisplay: "display-a", focusedWindow: 11)
        tracker.observe(displays(active: "2"), focusedDisplay: "display-a", focusedWindow: 11)
        XCTAssertEqual(workspaceChanges, ["1->", "->2"], "A fullscreen Space has no desktop number")
        XCTAssertEqual(hooks, ["startup", "focus-changed"])
        XCTAssertEqual(tracker.previousDesktop(on: displays(active: "2")[0]), "1", "Fullscreen is skipped in history")
    }

    func testPreviousFocusedWindowFollowsFocusChanges() {
        setUpWorkspacesForTests()
        let tracker = NativeActivityTracker()
        tracker.runHooks = { _, _ in }
        tracker.execWorkspaceChange = { _, _ in }
        tracker.observe(displays(active: "1"), focusedDisplay: "display-a", focusedWindow: 10)
        XCTAssertNil(tracker.previousFocusedWindow)
        tracker.observe(displays(active: "1"), focusedDisplay: "display-a", focusedWindow: 11)
        XCTAssertEqual(tracker.previousFocusedWindow, 10)
        tracker.observe(displays(active: "1"), focusedDisplay: "display-a", focusedWindow: nil)
        tracker.observe(displays(active: "1"), focusedDisplay: "display-a", focusedWindow: 12)
        XCTAssertEqual(tracker.previousFocusedWindow, 11, "An empty desktop in between is not a window to return to")
    }
}
