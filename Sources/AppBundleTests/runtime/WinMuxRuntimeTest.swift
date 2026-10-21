@testable import AppBundle
import Common
import AppKit
import HotKey
import XCTest

@MainActor
final class WinMuxRuntimeTest: WorkspaceTestCase {
    private func world() -> WinMuxRuntime {
        var value = defaultConfig
        value.persistentWorkspaces = []
        value.modes = [mainModeId: Mode(bindings: [:], tapBindings: [:])]
        value.onFocusChanged = []
        value.onFocusedMonitorChanged = []
        value.execOnWorkspaceChange = []
        return WinMuxRuntime(config: value)
    }

    private func display(_ index: Int, x: CGFloat) -> TestMonitor {
        let rect = Rect(topLeftX: x, topLeftY: 0, width: 1920, height: 1080)
        return TestMonitor(monitorAppKitNsScreenScreensId: index, name: "Display \(index)",
                           rect: rect, visibleRect: rect, isMain: index == 1)
    }

    func testIndependentRegistriesAndConfigurationWithOverlappingIDs() {
        let first = world(), second = world()
        let a = first.withValue {
            config.focusFollowsMouseDwell = 7
            return Workspace.get(byName: "1")
        }
        let b = second.withValue {
            XCTAssertNil(Workspace.existing(byName: "1"))
            XCTAssertEqual(config.focusFollowsMouseDwell, 250)
            return Workspace.get(byName: "1")
        }
        XCTAssertEqual(a.id, b.id) // IDs are scoped to a registry.
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 2)
        first.withValue {
            XCTAssertTrue(Workspace.existing(byName: "1") === a)
            XCTAssertEqual(config.focusFollowsMouseDwell, 7)
        }
    }

    func testNestedBindingRestoresOwnerAfterThrowAndSuspension() async {
        enum Failure: Error { case expected }
        let original = runtime, first = world(), second = world()
        await first.withValue {
            XCTAssertTrue(runtime === first)
            do {
                try await second.withValue {
                    await Task.yield()
                    XCTAssertTrue(runtime === second)
                    throw Failure.expected
                }
                XCTFail("Expected failure")
            } catch { }
            XCTAssertTrue(runtime === first)
        }
        XCTAssertTrue(runtime === original)
    }

    func testSuspendedChildKeepsOwnerWhenLegacyFixtureIsReplaced() async {
        let owner = world()
        let started = expectation(description: "child suspended")
        let finished = expectation(description: "child finished")
        var release: CheckedContinuation<Void, Never>?
        let child = owner.task {
            await withCheckedContinuation {
                release = $0
                started.fulfill()
            }
            XCTAssertTrue(runtime === owner)
            config.focusFollowsMouseDwell = 9
            finished.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        WinMuxRuntime.replaceForTests()
        let replacement = runtime
        release?.resume()
        await fulfillment(of: [finished], timeout: 1)
        await child.value
        XCTAssertTrue(runtime === replacement)
        XCTAssertNotEqual(config.focusFollowsMouseDwell, 9)
        XCTAssertEqual(owner.configuration.value.focusFollowsMouseDwell, 9)
    }

    func testFreshOwnerHasNoPreviousFocusOrNativeFocusHolds() {
        let first = world(), second = world()
        first.withValue {
            let a = Workspace.get(byName: "1"), b = Workspace.get(byName: "2")
            XCTAssertTrue(a.focusWorkspace())
            checkOnFocusChangedCallbacks()
            XCTAssertTrue(b.focusWorkspace())
            checkOnFocusChangedCallbacks()
            XCTAssertEqual(prevFocusedWorkspace?.name, "1")
            XCTAssertNotNil(prevFocus)
            holdFocusOnWorkspaceProject(workspaceProjectDefaultId, for: 30)
            holdFocusAfterLastWindowClosure(on: b, appPid: 42)
        }
        second.withValue {
            XCTAssertNil(prevFocusedWorkspace)
            XCTAssertNil(prevFocus)
            XCTAssertNil(prevPrevFocus)
            XCTAssertEqual(prevFocusedWorkspaceDate, .distantPast)
            XCTAssertNil(runtime.nativeFocus.projectHold)
            XCTAssertNil(runtime.nativeFocus.windowClosureHold)
        }
        first.withValue { XCTAssertEqual(focus.workspace.name, "2") }
    }

    func testDisplayOverridesAndSortedCacheBelongToOwnerAndInvalidateTogether() {
        let first = world(), second = world()
        first.withValue {
            setMonitorsForTests([display(1, x: 1920), display(2, x: 0)])
            XCTAssertEqual(sortedMonitors.map(\.name), ["Display 2", "Display 1"])
            XCTAssertEqual(mainMonitor.name, "Display 1")
        }
        second.withValue { XCTAssertEqual(monitors.map(\.name), ["Test Monitor"]) }
        first.withValue {
            setMonitorsForTests([display(1, x: 0), display(2, x: 1920)])
            XCTAssertEqual(sortedMonitors.map(\.name), ["Display 1", "Display 2"])
            runtime.displays.invalidate()
            XCTAssertEqual(sortedMonitors.map(\.name), ["Display 1", "Display 2"])
        }
    }

    func testScreenNotificationInvalidatesAllOwnedMonitorCaches() {
        let notifications = NotificationCenter()
        var snapshots: [Monitor] = [display(1, x: 0), display(2, x: 1920)]
        var listReads = 0, mainReads = 0
        weak var released: MonitorState?
        do {
            let state = MonitorState(readMonitors: { listReads += 1; return snapshots },
                                     readMain: { mainReads += 1; return snapshots[0] },
                                     notifications: notifications, observeChanges: true)
            released = state
            for _ in 0..<20 {
                XCTAssertEqual(state.all().count, 2)
                XCTAssertEqual(state.sorted().first?.name, "Display 1")
                XCTAssertEqual(state.main().rect.minX, 0)
            }
            XCTAssertEqual(listReads, 1)
            XCTAssertEqual(mainReads, 1)
            snapshots = [display(1, x: 1920), display(2, x: 0)]
            notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            XCTAssertEqual(state.sorted().first?.name, "Display 2")
            XCTAssertEqual(state.main().rect.minX, 1920)
            XCTAssertEqual(listReads, 2)
            XCTAssertEqual(mainReads, 2)
        }
        XCTAssertNil(released)
        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(listReads, 2)
        XCTAssertEqual(mainReads, 2)
    }

    func testMonitorFrameNormalizationSupportsDisplaysAboveAndBelowMain() {
        XCTAssertEqual(CGRect(x: 0, y: 0, width: 1920, height: 1080)
            .monitorFrameNormalized(mainHeight: 1080).topLeftCorner, .zero)
        XCTAssertEqual(CGRect(x: -2560, y: 1080, width: 2560, height: 1440)
            .monitorFrameNormalized(mainHeight: 1080).topLeftCorner, CGPoint(x: -2560, y: -1440))
        XCTAssertEqual(CGRect(x: 1920, y: -1440, width: 2560, height: 1440)
            .monitorFrameNormalized(mainHeight: 1080).topLeftCorner, CGPoint(x: 1920, y: 1080))
    }

    func testModeAndSequenceStateDoNotLeakToAnotherOwner() {
        let first = world(), second = world()
        first.withValue {
            activeMode = "custom"
            sequenceBindingsPrefixKeys = [.escape]
            noteSequencePrefixKeyPressed(.escape)
            setHotkeysSuspended(true)
        }
        second.withValue {
            XCTAssertEqual(activeMode, mainModeId)
            XCTAssertTrue(sequenceBindingsPrefixKeys.isEmpty)
            XCTAssertNil(runtime.hotkeys.lastSequencePrefixKey)
            XCTAssertFalse(runtime.hotkeys.hotkeysSuspended)
        }
        first.withValue { XCTAssertEqual(activeMode, "custom") }
    }

    func testConfigurationReloadPublicationFailureAndDryRunStayInOwner() async throws {
        let first = world(), second = world()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.toml")
        let originalURL = second.configuration.url
        var args = ReloadConfigCmdArgs(rawArgs: [])
        args.noGui = true
        try "config-version = 2\nfocus-follows-mouse-dwell = 3\n[mode.main.binding]\n"
            .write(to: file, atomically: true, encoding: .utf8)
        try await first.withValue {
            activeMode = nil
            var output = ""
            let loaded = try await reloadConfig(args: args, forceConfigUrl: file, stdout: &output)
            XCTAssertTrue(loaded)
            XCTAssertEqual(config.focusFollowsMouseDwell, 3)
            XCTAssertEqual(configUrl, file)
            XCTAssertNil(lastConfigReloadError)
            try "invalid = [".write(to: file, atomically: true, encoding: .utf8)
            let invalid = try await reloadConfig(args: args, forceConfigUrl: file, stdout: &output)
            XCTAssertFalse(invalid)
            XCTAssertEqual(config.focusFollowsMouseDwell, 3)
            XCTAssertEqual(configUrl, file)
            XCTAssertNotNil(lastConfigReloadError)
            try "config-version = 2\nfocus-follows-mouse-dwell = 8\n[mode.main.binding]\n"
                .write(to: file, atomically: true, encoding: .utf8)
            args.dryRun = true
            let validated = try await reloadConfig(args: args, forceConfigUrl: file, stdout: &output)
            XCTAssertTrue(validated)
            XCTAssertEqual(config.focusFollowsMouseDwell, 3)
            XCTAssertNotNil(lastConfigReloadError) // Validation does not publish diagnostics either.
        }
        second.withValue {
            XCTAssertEqual(config.focusFollowsMouseDwell, 250)
            XCTAssertEqual(configUrl, originalURL)
            XCTAssertNil(lastConfigReloadError)
        }
    }

    func testReloadGatesDoNotBlockIndependentOwners() async {
        let first = world(), second = world()
        await first.configuration.reloadGate.acquire()
        defer { first.configuration.reloadGate.release() }
        let completed = expectation(description: "independent gate available")
        let task = Task { @MainActor in
            await second.configuration.reloadGate.acquire()
            second.configuration.reloadGate.release()
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)
        await task.value
    }

    func testRecoverySnapshotsDoNotCrossRuntimeBoundary() async throws {
        let first = world(), second = world()
        first.withValue {
            let workspace = Workspace.get(byName: "saved")
            let window = TestWindow.new(id: 77, parent: workspace.rootTilingContainer)
            window.restartIdentity = RestartWindowIdentity(bundleId: "test.editor", pid: 10,
                launchDate: Date(timeIntervalSince1970: 10), title: "Saved",
                documentURL: nil, accessibilityIdentifier: nil)
            syncClosedWindowsCacheToCurrentWorld()
            let envelope = makeRestartEnvelope()
            preparePersistedFrozenWorldForStartup(envelope)
            XCTAssertEqual(pendingRestartWindowCount, 1)
            window.unbindFromParent()
        }
        try await second.withValue {
            XCTAssertEqual(pendingRestartWindowCount, 0)
            XCTAssertNil(Workspace.existing(byName: "saved"))
            let workspace = Workspace.get(byName: "new")
            let window = TestWindow.new(id: 78, parent: workspace.rootTilingContainer)
            let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
            XCTAssertFalse(restored)
            window.unbindFromParent()
        }
        first.withValue { XCTAssertEqual(pendingRestartWindowCount, 1) }
    }

    func testScopedOwnerReleasesAfterUse() {
        weak var observed: WinMuxRuntime?
        do {
            let owner = world()
            observed = owner
            owner.withValue {
                _ = Workspace.get(byName: "1")
                setMonitorsForTests([display(1, x: 0)])
                _ = sortedMonitors
                _ = focus
            }
        }
        XCTAssertNil(observed)
    }
}
