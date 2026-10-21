@testable import AppBundle
import AppKit
import Common
import XCTest

/// Every suspension is controlled by a continuation. Seed and ordered actions are
/// included in assertion messages; these fixtures perform no native window work.
@MainActor
final class OverlappingRuntimeEventsTest: WorkspaceTestCase {
    private let seed: UInt64 = 0x574D_2026
    private var trace: [String] = []
    private func boundary(_ event: String, windows: [Window]? = nil, file: StaticString = #filePath, line: UInt = #line) {
        trace.append(event)
        XCTAssertEqual(runtime.modelInvariantViolations(expectedWindows: windows), [],
                       "seed=\(seed) events=\(trace)", file: file, line: line)
    }

    func testWorkspaceSwitchAndMoveWhileNativeObservationIsPending() async throws {
        let a = Workspace.get(byName: "a"), b = Workspace.get(byName: "b")
        let window = TestWindow.new(id: 41, parent: a.rootTilingContainer)
        var resume: CheckedContinuation<(fullscreen: Bool, minimized: Bool)?, Never>?
        let started = expectation(description: "native state suspended")
        window.nativeStateReader = {
            await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        let task = runtime.throwingTask { try await normalizeLayoutReason() }
        await fulfillment(of: [started], timeout: 2)
        boundary("observation pending", windows: [window])
        _ = b.focusWorkspace()
        window.bind(to: b.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        window.nativeStateReader = { (false, false) }
        boundary("switch then explicit move", windows: [window])
        resume?.resume(returning: (true, false))
        try await task.value
        boundary("old fullscreen observation returned", windows: [window])
        XCTAssertTrue(window.nodeWorkspace === b, "seed=\(seed) events=\(trace)")
        XCTAssertTrue(window.parent is TilingContainer)
    }

    func testCloseLastTileAndCancelRefreshWhileNativeObservationIsPending() async throws {
        let workspace = Workspace.get(byName: "close")
        let tile = TestWindow.new(id: 42, parent: workspace.rootTilingContainer)
        let floating = TestWindow.new(id: 43, parent: workspace)
        var resume: CheckedContinuation<(fullscreen: Bool, minimized: Bool)?, Never>?
        let started = expectation(description: "native state suspended")
        tile.nativeStateReader = { await withCheckedContinuation { resume = $0; started.fulfill() } }
        let task = runtime.throwingTask { try await normalizeLayoutReason() }
        await fulfillment(of: [started], timeout: 2)
        tile.closeAxWindow()
        boundary("last tile closes; floating survives", windows: [floating])
        task.cancel()
        resume?.resume(returning: (true, false))
        do { try await task.value } catch is CancellationError { }
        boundary("cancelled native result returned", windows: [floating])
        XCTAssertNil(tile.parent)
        XCTAssertTrue(floating.parent === workspace)
    }

    func testTopologyReorderDisconnectReconnectDuringHeldRefresh() async throws {
        func display(_ id: Int, _ x: CGFloat) -> TestMonitor {
            let rect = Rect(topLeftX: x, topLeftY: 0, width: 1200, height: 900)
            return TestMonitor(monitorAppKitNsScreenScreensId: id, name: "\(id)", rect: rect, visibleRect: rect, isMain: id == 1)
        }
        let first = display(1, 0), second = display(2, -1200)
        setMonitorsForTests([first, second]); Workspace.reconcileWorkspaceState()
        var resume: CheckedContinuation<Void, Never>?
        let started = expectation(description: "refresh held")
        setScheduledRefreshOverrideForTests { _, _ in await withCheckedContinuation { resume = $0; started.fulfill() } }
        scheduleRefreshSession(.globalObserver("fixture"))
        await fulfillment(of: [started], timeout: 2)
        boundary("two displays refresh held")
        setMonitorsForTests([first]); Workspace.reconcileWorkspaceState()
        boundary("secondary disconnected")
        setMonitorsForTests([second, first]); Workspace.reconcileWorkspaceState()
        boundary("secondary reconnected reordered negative origin")
        resume?.resume(); try await waitForScheduledRefreshForTests()
        boundary("older refresh returned")
    }

    func testValidAndInvalidReloadDuringQueuedRefresh() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.toml")
        var resume: CheckedContinuation<Void, Never>?
        let started = expectation(description: "refresh held")
        var calls = 0
        setScheduledRefreshOverrideForTests { _, _ in
            calls += 1
            if calls == 1 { await withCheckedContinuation { resume = $0; started.fulfill() } }
        }
        scheduleRefreshSession(.globalObserver("fixture"))
        await fulfillment(of: [started], timeout: 2)
        scheduleRefreshSession(.configAutoReload)
        var args = ReloadConfigCmdArgs(rawArgs: []); args.noGui = true
        var output = ""
        try "config-version = 2\nfocus-follows-mouse-dwell = 17\n[mode.main.binding]\n".write(to: file, atomically: true, encoding: .utf8)
        let valid = try await reloadConfig(args: args, forceConfigUrl: file, stdout: &output)
        XCTAssertTrue(valid)
        boundary("valid reload while refresh held")
        try "invalid = [".write(to: file, atomically: true, encoding: .utf8)
        let invalid = try await reloadConfig(args: args, forceConfigUrl: file, stdout: &output)
        XCTAssertFalse(invalid); XCTAssertEqual(config.focusFollowsMouseDwell, 17)
        boundary("invalid reload preserves published config")
        resume?.resume(); try await waitForScheduledRefreshForTests()
        boundary("queued refresh drained")
        XCTAssertEqual(calls, 2)
    }

    func testInvalidationAndReplacementDoNotDrainStalePendingWork() async throws {
        let owner = runtime
        var resume: CheckedContinuation<Void, Never>?
        let started = expectation(description: "refresh held")
        var calls = 0
        setScheduledRefreshOverrideForTests { _, _ in
            calls += 1
            await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        scheduleRefreshSession(.globalObserver("fixture"))
        await fulfillment(of: [started], timeout: 2)
        scheduleRefreshSession(.configAutoReload)
        let heldTask = owner.refresh.activeRefreshTask
        owner.refresh.invalidate() // shared disable/shutdown cancellation boundary
        boundary("management invalidated")
        WinMuxRuntime.replaceForTests()
        let replacement = runtime
        resume?.resume()
        try await heldTask?.value
        XCTAssertTrue(runtime === replacement)
        XCTAssertNil(owner.refresh.pendingRefreshRequest)
        XCTAssertNil(replacement.refresh.activeRefreshTask)
        XCTAssertEqual(calls, 1)
        boundary("replacement runtime remains untouched")
    }

    func testFixedSeedRapidSwitchesAndLateNativeCacheResults() {
        let a = Workspace.get(byName: "a"), b = Workspace.get(byName: "b")
        let window = TestWindow.new(id: 44, parent: a.rootTilingContainer)
        var state = seed
        for index in 0..<128 {
            state = state &* 6364136223846793005 &+ 1
            let token = window.nativeStateObservationToken()
            _ = (state & 1 == 0 ? a : b).focusWorkspace()
            window.invalidateLastKnownNativeState()
            window.recordObservedNativeState(fullscreen: true, minimized: false, token: token)
            XCTAssertNil(window.lastKnownNativeFullscreen)
            boundary("switch \(index) stale native result rejected", windows: [window])
        }
    }
}
