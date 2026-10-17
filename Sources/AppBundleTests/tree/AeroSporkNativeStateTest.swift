@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class AeroSporkNativeStateTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws { setUpWorkspacesForTests() }

    func testUnansweredStateCannotUnminimizeOrExitFullscreen() async throws {
        for fullscreen in [true, false] {
            let workspace = Workspace.get(byName: "unknown-state")
            let window = TestWindow.new(id: fullscreen ? 8101 : 8102, parent: workspace.rootTilingContainer)
            window.nativeIsMacosFullscreen = fullscreen
            window.nativeIsMacosMinimized = !fullscreen
            try await normalizeLayoutReason()
            let parent = window.parent
            window.nativeStateReader = { nil }
            window.invalidateLastKnownNativeState()
            try await normalizeLayoutReason()
            XCTAssertTrue(window.parent === parent)
        }
    }

    func testAnInvalidatedObservationCannotMutateTheTree() async throws {
        let workspace = Workspace.get(byName: "stale-state")
        let window = TestWindow.new(id: 8103, parent: workspace.rootTilingContainer)
        var reads = 0
        window.nativeStateReader = {
            reads += 1
            if reads == 1 {
                window.invalidateLastKnownNativeState()
                return (true, false) // stale answer, delivered after its invalidation
            }
            return (false, false)
        }
        try await normalizeLayoutReason()
        XCTAssertTrue(window.parent is TilingContainer)
        XCTAssertEqual(window.lastKnownNativeFullscreen, false)
    }

    func testNativeBookkeepingDoesNotPromoteABackgroundWindow() async throws {
        let workspace = Workspace.get(byName: "mru-state")
        let foreground = TestWindow.new(id: 8104, parent: workspace.rootTilingContainer)
        let background = TestWindow.new(id: 8105, parent: workspace.rootTilingContainer)
        foreground.markAsMostRecentChild()
        background.nativeIsMacosFullscreen = true
        try await normalizeLayoutReason()
        XCTAssertTrue(workspace.mostRecentWindowRecursive === foreground)
        XCTAssertTrue(background.parent is MacosFullscreenWindowsContainer)
    }

    func testAWorkspaceMoveDuringEitherNativeReadIsNeverUndone() async throws {
        for moveOnRead in [1, 2] {
            setUpWorkspacesForTests()
            let source = focus.workspace
            let destination = Workspace.get(byName: "user-destination")
            let window = TestWindow.new(id: UInt32(8110 + moveOnRead), parent: source.rootTilingContainer)
            var reads = 0
            window.nativeStateReader = {
                reads += 1
                if reads == moveOnRead { window.bind(to: destination.rootTilingContainer, adaptiveWeight: 1, index: 0) }
                return (true, false)
            }
            try await normalizeLayoutReason()
            XCTAssertTrue(window.nodeWorkspace === destination, "A late native state must not move the window back")
        }
    }

    func testCancellationBeforeMutationLeavesTheWindowInPlace() async {
        let workspace = Workspace.get(byName: "cancel-state")
        let window = TestWindow.new(id: 8106, parent: workspace.rootTilingContainer)
        window.nativeIsMacosFullscreen = true
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await normalizeLayoutReason()
        }
        guard case .failure(let error) = await task.result, error is CancellationError else { return XCTFail("Expected cancellation") }
        XCTAssertTrue(window.parent is TilingContainer)
    }

    func testUnknownFocusDoesNotSpendTheLastConfirmedAnswerOrUndoASwitch() async throws {
        let first = focus.workspace
        let window = TestWindow.new(id: 8107, parent: first.rootTilingContainer)
        XCTAssertTrue(window.focusWindow())
        updateFocusCache(window)
        let second = Workspace.get(byName: "explicit-switch")
        TestWindow.new(id: 8108, parent: second.rootTilingContainer)
        XCTAssertTrue(activateWorkspaceForUser(second, on: mainMonitor))
        let previous = appForTests
        defer { appForTests = previous }
        appForTests = UnknownFocusProbeApp()
        try await runRefreshSessionBlocking(.ax(kAXFocusedWindowChangedNotification as String), layoutWorkspaces: false)
        XCTAssertTrue(focus.workspace === second)
        updateFocusCache(window) // the busy app finally answers, naming its old window
        XCTAssertTrue(focus.workspace === second, "An unknown read must not make this stale answer look like a new focus change")
    }

    func testOneActualTimeoutSkipsQueuedReadsButOtherAppsAndNextPassStillRun() {
        let budget = AXReadBudget()
        var reads = 0
        let first: Result<Int, AXReadFailure> = budget.read(pid: 10) { reads += 1; return .failure(AXReadFailure(code: .cannotComplete)) }
        XCTAssertThrowsError(try first.get())
        let skipped: Result<Int, AXReadFailure> = budget.read(pid: 10) { reads += 1; return .success(1) }
        XCTAssertThrowsError(try skipped.get())
        let other = budget.read(pid: 11) { reads += 1; return .success(2) }
        XCTAssertEqual(try other.get(), 2)
        let next = AXReadBudget().read(pid: 10) { reads += 1; return .success(3) }
        XCTAssertEqual(try next.get(), 3)
        XCTAssertEqual(reads, 3)
        let unavailable: Result<Int?, AXReadFailure> = budget.read(pid: 12) { .success(nil) }
        XCTAssertNil(try unavailable.get())
        XCTAssertTrue(budget.permits(12), "An absent attribute is not an app timeout")
    }
}

private final class UnknownFocusProbeApp: AbstractApp {
    let pid: Int32 = -8107
    let rawAppBundleId: String? = "test.unknown-focus"
    let name: String? = "Unknown focus probe"
    let execPath: String? = nil
    let bundlePath: String? = nil
    @MainActor func getFocusedWindow() async throws -> Window? { throw NativeFocusUnknown() }
}
