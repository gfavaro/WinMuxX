@testable import AppBundle
import AppKit
import Common
import XCTest

final class RefreshFocusSyncTest: XCTestCase {
    func testActivationRaisesOnlyMatchingWindowOnAnotherWorkspace() {
        let activation = RefreshActivationContext(generation: 1, workspaceName: "1", pid: 7)
        XCTAssertTrue(activation.shouldRaise(currentWorkspace: "2", nativeWindowId: 42, logicalWindowId: 42, frontmostPid: 7, targetPid: 7))
        XCTAssertFalse(activation.shouldRaise(currentWorkspace: "1", nativeWindowId: 42, logicalWindowId: 42, frontmostPid: 7, targetPid: 7))
        XCTAssertFalse(activation.shouldRaise(currentWorkspace: "2", nativeWindowId: 42, logicalWindowId: 43, frontmostPid: 7, targetPid: 7))
        XCTAssertFalse(activation.shouldRaise(currentWorkspace: "2", nativeWindowId: nil, logicalWindowId: nil, frontmostPid: 7, targetPid: 7))
        XCTAssertFalse(activation.shouldRaise(currentWorkspace: "2", nativeWindowId: 42, logicalWindowId: 42, frontmostPid: 8, targetPid: 7))
        XCTAssertFalse(activation.shouldRaise(currentWorkspace: "2", nativeWindowId: 42, logicalWindowId: 42, frontmostPid: 7, targetPid: 8))
    }

    @MainActor
    func testActivationSurvivesCoalescingWithHeavyEvents() async throws {
        for heavy in [RefreshSessionEvent.ax(kAXWindowCreatedNotification as String),
                      .ax(kAXUIElementDestroyedNotification as String),
                      .globalObserver(NSWorkspace.didWakeNotification.rawValue)] {
            for activationFirst in [true, false] {
                setUpWorkspacesForTests()
                TrayMenuModel.shared.isEnabled = true
                var events: [RefreshSessionEvent] = []
                var release = false
                setScheduledRefreshOverrideForTests { event, _ in
                    events.append(event)
                    if events.count == 1 {
                        while !release { await Task.yield() }
                    }
                }
                defer { setScheduledRefreshOverrideForTests(nil) }
                scheduleRefreshSession(.hotkeyBinding)
                while events.isEmpty { await Task.yield() }
                let activation = RefreshSessionEvent.globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue)
                scheduleRefreshSession(activationFirst ? activation : heavy)
                scheduleRefreshSession(activationFirst ? heavy : activation)
                recordRefreshActivation(workspaceName: "origin", pid: 7)
                release = true
                try await waitForScheduledRefreshForTests()
                XCTAssertEqual(events.count, 2)
                XCTAssertEqual(events.last?.description, heavy.description)
                XCTAssertEqual(pendingRefreshActivationForTests()?.workspaceName, "origin")
                recordRefreshActivation(workspaceName: "new-origin", pid: 8)
                XCTAssertEqual(pendingRefreshActivationForTests()?.pid, 8)
            }
        }
    }

    @MainActor
    func testLightSessionPreservesActivationAndPendingHeavyRefresh() async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        var events: [String] = []
        setScheduledRefreshOverrideForTests { event, _ in
            events.append(event.description)
            if events.count == 1 { try await Task.sleep(nanoseconds: 10_000_000_000) }
        }
        defer { setScheduledRefreshOverrideForTests(nil) }
        scheduleRefreshSession(.hotkeyBinding)
        while events.isEmpty { await Task.yield() }
        let wake = RefreshSessionEvent.globalObserver(NSWorkspace.didWakeNotification.rawValue)
        scheduleRefreshSession(wake)
        recordRefreshActivation(workspaceName: "origin", pid: 7)
        let activation = pendingRefreshActivationForTests()
        try await runLightSession(.hotkeyBinding, .forceRun) { }
        try await waitForScheduledRefreshForTests()
        XCTAssertEqual(events, [RefreshSessionEvent.hotkeyBinding.description, wake.description])
        XCTAssertEqual(pendingRefreshActivationForTests(), activation)
    }

    @MainActor
    func testSuccessfulReconciliationConsumesActivation() async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        setBlockingRefreshOverridesForTests(refresh: {}, normalizeLayoutReason: {})
        defer { setBlockingRefreshOverridesForTests() }
        recordRefreshActivation(workspaceName: focus.workspace.name, pid: 7)
        try await runRefreshSessionBlocking(.hotkeyBinding)
        XCTAssertNil(pendingRefreshActivationForTests())
    }

    @MainActor
    func testReconciliationRetainsActivationArrivingDuringRefresh() async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        setBlockingRefreshOverridesForTests(refresh: {
            recordRefreshActivation(workspaceName: "new-origin", pid: 8)
        }, normalizeLayoutReason: {})
        defer { setBlockingRefreshOverridesForTests() }
        recordRefreshActivation(workspaceName: "old-origin", pid: 7)
        try await runRefreshSessionBlocking(.hotkeyBinding)
        XCTAssertEqual(pendingRefreshActivationForTests()?.pid, 8)
    }

    @MainActor
    func testNativeSelectionWinsOverWorkspacePreviousWindow() async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        setBlockingRefreshOverridesForTests(refresh: {}, normalizeLayoutReason: {})
        defer { setBlockingRefreshOverridesForTests() }
        let origin = focus.workspace
        let destination = Workspace.get(byName: "destination")
        let previous = TestWindow.new(id: 101, parent: destination.rootTilingContainer)
        let selected = TestWindow.new(id: 102, parent: destination.rootTilingContainer)
        _ = previous.focusWindow()
        _ = origin.focusWorkspace()
        selected.nativeFocus()
        recordRefreshActivation(workspaceName: origin.name, pid: 0)
        try await runRefreshSessionBlocking(.globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue))
        XCTAssertEqual(focus.workspace, destination)
        XCTAssertEqual(focus.windowOrNil?.windowId, selected.windowId)
        XCTAssertNil(pendingRefreshActivationForTests())
    }

    @MainActor
    func testShouldNotSyncFocusBackToPopupWindow() {
        setUpWorkspacesForTests()

        let popup = TestWindow.new(id: 1, parent: macosPopupWindowsContainer)

        XCTAssertFalse(shouldSyncFocusBackToMacOs(nativeFocused: popup, frontmostActivationPolicy: .accessory))
    }

    @MainActor
    func testShouldNotSyncFocusBackToAccessoryAppWithoutFocusedWindow() {
        XCTAssertFalse(shouldSyncFocusBackToMacOs(nativeFocused: nil, frontmostActivationPolicy: .accessory))
    }

    @MainActor
    func testShouldSyncFocusBackToRegularWorkspaceWindow() {
        setUpWorkspacesForTests()

        let window = TestWindow.new(id: 1, parent: focus.workspace)

        XCTAssertTrue(shouldSyncFocusBackToMacOs(nativeFocused: window, frontmostActivationPolicy: .regular))
    }
}
