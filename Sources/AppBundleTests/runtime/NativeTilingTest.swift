import AppKit
import Common
import XCTest
@testable import AppBundle
@testable import NativeSpaces

@MainActor
final class NativeTilingTest: WorkspaceTestCase {
    private func nativeWorkspace() -> Workspace {
        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let display = TestMonitor(displayUUID: "display-a", monitorAppKitNsScreenScreensId: 1,
            name: "fixture", rect: rect, visibleRect: rect, isMain: true)
        setMonitorsForTests([display])
        let snapshot = NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a",
            activeSpaceID: "1", spaces: [NativeSpace(id: "1", uuid: "desktop-a", type: 0)])],
            windows: (1...6).map { NativeWindowMembership(windowID: UInt32($0), spaceIDs: ["1"]) },
            readMilliseconds: 0, capturedAt: .now)
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(snapshot, for: inventory.invalidate()))
        runtime.workspaceBackend.nativeLayouts.reconcile(inventory, displays: [display])
        return runtime.workspaceBackend.nativeLayouts.activeWorkspace(on: "display-a")!
    }

    func testNativeTilingNeverAcquiresVirtualLifecycleOrRecovery() {
        _ = nativeWorkspace()
        let capabilities = runtime.workspaceBackend.capabilities
        XCTAssertTrue(capabilities.tilesWindows)
        XCTAssertFalse(capabilities.ownsWorkspaceLifecycle)
        XCTAssertFalse(capabilities.activatesWorkspaces)
        XCTAssertFalse(capabilities.relocatesWorkspaces)
        XCTAssertFalse(capabilities.parksInactiveWindows)
        XCTAssertFalse(capabilities.usesVirtualRecovery)
    }

    func testFrameDiagnosticsIdentifyRetainedWindowsWithoutClaimingActualAXFrames() async throws {
        let workspace = nativeWorkspace()
        let visible = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let concealed = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        concealed.nativeLayoutEligible = false
        TestWindow.new(id: 3, parent: workspace)
        try await workspace.layoutWorkspace()
        let rows = nativeWindowFrameDiagnostics(runtime.workspaceBackend.nativeLayouts)
        XCTAssertEqual(rows.map(\.windowID), [1, 2, 3])
        XCTAssertEqual(rows.map(\.spaceUUID), ["desktop-a", "desktop-a", "desktop-a"])
        XCTAssertEqual(rows.map(\.eligible), [true, false, true])
        XCTAssertNotNil(rows[0].desiredFrame)
        XCTAssertNil(rows[1].desiredFrame)
        XCTAssertTrue(rows[2].floating)
        XCTAssertNil(rows[2].desiredFrame)
        XCTAssertTrue(visible.nodeWorkspace === workspace)
    }

    func testQueuedCommandCannotFollowFocusToAnotherWorkspaceOrWindow() throws {
        let workspace = nativeWorkspace()
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        _ = first.focusWindow()
        let command = try XCTUnwrap(parseCommand("resize width +20").unwrap().0)
        let layouts = runtime.workspaceBackend.nativeLayouts
        let initial = focus
        let target = try XCTUnwrap(NativeCommandTargetFence([command], env: .defaultEnv, defaultFocus: initial, layouts: layouts))
        XCTAssertTrue(target.matches(layouts, defaultFocus: initial))
        _ = second.focusWindow()
        XCTAssertFalse(target.matches(layouts, defaultFocus: focus))
        XCTAssertTrue(target.matches(layouts, defaultFocus: focus, allowDefaultFocusChanges: true))
        let other = Workspace.get(byName: "other-desktop")
        XCTAssertFalse(target.matches(layouts, defaultFocus: LiveFocus(windowOrNil: nil, workspace: other)))
        let explicitCommand = try XCTUnwrap(parseCommand("resize --window-id 1 width +20").unwrap().0)
        let explicit = try XCTUnwrap(NativeCommandTargetFence([explicitCommand], env: .defaultEnv,
            defaultFocus: initial, layouts: layouts))
        XCTAssertTrue(explicit.matches(layouts, defaultFocus: focus)) // Explicit target is independent of app focus.
        first.bind(to: other.rootTilingContainer, adaptiveWeight: 1, index: 0)
        XCTAssertFalse(explicit.matches(layouts, defaultFocus: focus))
        first.unbindFromParent()
        TestApp.shared._windows.removeAll { $0 === first }
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        XCTAssertFalse(explicit.matches(layouts, defaultFocus: focus)) // Reused IDs cannot inherit a queued command.
        XCTAssertTrue(second.nodeWorkspace === workspace)
    }

    func testFloatingToTilingCannotBindAfterItsNativeReadWasInvalidated() async throws {
        let workspace = nativeWorkspace()
        let window = TestWindow.new(id: 1, parent: workspace)
        _ = window.focusWindow()
        let layouts = runtime.workspaceBackend.nativeLayouts
        defer { window.sizeReader = nil }
        window.sizeReader = {
            await Task.yield()
            var stopped = NativeWorkspaceInventory()
            stopped.stop()
            layouts.reconcile(stopped, displays: [mainMonitor])
            return CGSize(width: 500, height: 400)
        }
        let result = try await NativeTilingCommandScope.$active.withValue(true) {
            try await parseCommand("layout tiling").cmdOrDie.run(.defaultEnv, .emptyStdin)
        }
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.joined().contains("changed"))
        XCTAssertTrue(window.parent === workspace)
    }

    func testQueuedCommandIsRevokedByObservedNativeSpaceSwitch() throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let window = TestWindow.new(id: 1, parent: root)
        _ = window.focusWindow()
        let layouts = runtime.workspaceBackend.nativeLayouts
        let command = try XCTUnwrap(parseCommand("resize width +20").unwrap().0)
        let target = try XCTUnwrap(NativeCommandTargetFence([command], env: .defaultEnv,
            defaultFocus: focus, layouts: layouts))
        let next = NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a", activeSpaceID: "2",
            spaces: [NativeSpace(id: "1", uuid: "desktop-a", type: 0), NativeSpace(id: "2", uuid: "desktop-b", type: 0)])],
            windows: [NativeWindowMembership(windowID: 1, spaceIDs: ["1"])], readMilliseconds: 0, capturedAt: .now)
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(next, for: inventory.invalidate()))
        layouts.reconcile(inventory, displays: [mainMonitor])
        let incoming = try XCTUnwrap(layouts.activeWorkspace(on: "display-a"))
        XCTAssertFalse(target.matches(layouts, defaultFocus: incoming.toLiveFocus(), allowDefaultFocusChanges: true))
        XCTAssertTrue(layouts.retainedByUUID["desktop-a"] === workspace)
        XCTAssertTrue(workspace.rootTilingContainer === root)
        XCTAssertTrue(window.parent === root)
        XCTAssertNil(window.lastAppliedLayoutPhysicalRect)
    }

    func testCommandSequenceRejectsRevokedNativeTargetBeforeMutation() async throws {
        let workspace = nativeWorkspace()
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        _ = window.focusWindow()
        let root = workspace.rootTilingContainer
        let result = try await NativeTilingCommandScope.$validateTarget.withValue({ false }) {
            try await NativeTilingCommandScope.$active.withValue(true) {
                try await parseCommand("workspace-layout master").cmdOrDie.run(.defaultEnv, .emptyStdin)
            }
        }
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.joined().contains("target changed"))
        XCTAssertEqual(workspace.arrangement, .dwindle)
        XCTAssertTrue(workspace.rootTilingContainer === root)
        XCTAssertTrue(root.children.first === window)
    }

    func testNativeAccordionOverlapsItsWindowsWithoutParkingThem() async throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let accordion = TilingContainer(parent: root, adaptiveWeight: 1, .h, .stacked, index: 0)
        let a = TestWindow.new(id: 1, parent: accordion)
        let b = TestWindow.new(id: 2, parent: accordion)
        b.markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        let first = try XCTUnwrap(a.lastAppliedLayoutPhysicalRect)
        let second = try XCTUnwrap(b.lastAppliedLayoutPhysicalRect)
        XCTAssertLessThan(first.minX, second.minX, "Each window peeks out by the padding")
        XCTAssertGreaterThan(first.maxX, second.minX, "Accordion windows overlap")
        XCTAssertEqual(root.allStackingContainersRecursive.map { $0 === accordion }, [true], "The active one is raised")
    }

    func testNativeTabbedGroupStacksInactiveTabsAtTheActiveFrame() async throws {
        config.windowTabs.enabled = true
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let tabs = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .h, .tabGroup, index: 0)
        let a = TestWindow.new(id: 1, parent: tabs)
        let b = TestWindow.new(id: 2, parent: tabs)
        b.markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        let active = try XCTUnwrap(b.lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(a.lastAppliedLayoutPhysicalRect, active, "Inactive tabs wait behind, never parked")
        XCTAssertTrue(a.isInactiveWindowTab)
        XCTAssertFalse(b.isInactiveWindowTab)
    }

    func testIncomingSpaceReadPreservesUnqueriedDisplaysAndRetiresOutgoingPresentation() throws {
        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        let displays = (0..<3).map { index -> TestMonitor in
            let rect = Rect(topLeftX: CGFloat(index * 1920), topLeftY: 0, width: 1920, height: 1080)
            return TestMonitor(displayUUID: "display-\(index)", monitorAppKitNsScreenScreensId: index + 1,
                name: "fixture", rect: rect, visibleRect: rect, isMain: index == 0)
        }
        setMonitorsForTests(displays)
        func snapshot(active: String, partial: Bool) -> NativeSpacesSnapshot {
            NativeSpacesSnapshot(displays: (0..<3).map { index in
                NativeSpaceDisplay(identifier: "display-\(index)", activeSpaceID: index == 0 ? active : "\(index + 1)",
                    spaces: (index == 0 ? ["1", "4"] : ["\(index + 1)"]).map { NativeSpace(id: $0, uuid: "desktop-\($0)", type: 0) })
            }, windows: (partial ? [4] : [1, 2, 3, 4]).map {
                NativeWindowMembership(windowID: UInt32($0), spaceIDs: ["\($0)"])
            }, readMilliseconds: 0, capturedAt: .now, reconciliationSpaceIDs: partial ? ["4"] : nil)
        }
        func publish(_ snapshot: NativeSpacesSnapshot) {
            var inventory = NativeWorkspaceInventory()
            XCTAssertTrue(inventory.publish(snapshot, for: inventory.invalidate()))
            runtime.workspaceBackend.nativeLayouts.reconcile(inventory, displays: displays)
        }
        let layouts = runtime.workspaceBackend.nativeLayouts
        publish(snapshot(active: "1", partial: false))
        let windows = try (1...4).map { id in
            TestWindow.new(id: UInt32(id), parent: try XCTUnwrap(layouts.currentBySpaceID["\(id)"]).rootTilingContainer)
        }
        let roots = windows.map(\.parent)
        publish(snapshot(active: "4", partial: true))
        NativeWindowReconciler.updateEligibility(snapshot(active: "4", partial: true), windows: windows,
            ownerPIDs: [4: TestApp.shared.pid], layouts: layouts)
        XCTAssertFalse(windows[0].nativeLayoutEligible)
        XCTAssertTrue(windows[1].nativeLayoutEligible)
        XCTAssertTrue(windows[2].nativeLayoutEligible)
        XCTAssertTrue(windows[3].nativeLayoutEligible)
        for index in windows.indices { XCTAssertTrue(windows[index].parent === roots[index]) }
        // Retained presentation is not fresh membership or frame authority.
        XCTAssertNil(layouts.registration(for: 2))
        XCTAssertNil(layouts.registration(for: 3))
        XCTAssertNotNil(layouts.registration(for: 4))
    }

    func testHiddenWindowLeavesGeometryButRetainsTreeAndDwindleShares() throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let first = TestWindow.new(id: 1, parent: root)
        let hidden = TestWindow.new(id: 2, parent: root)
        let last = TestWindow.new(id: 3, parent: root)
        root.dwindleChildRatios = [0.2, 0.3, 0.5]
        hidden.nativeLayoutEligible = false
        XCTAssertEqual(root.frameLayoutChildren, [first, last])
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1400, height: 800)
        let frames = root.dwindleChildFrames(in: rect, gaps: ResolvedGaps(gaps: .zero, monitor: mainMonitor))
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].width, 400, accuracy: 0.001)
        XCTAssertEqual(frames[1].width, 1000, accuracy: 0.001)
        XCTAssertEqual(root.children, [first, hidden, last])
        XCTAssertEqual(root.dwindleChildRatios, [0.2, 0.3, 0.5])
        hidden.nativeLayoutEligible = true
        XCTAssertEqual(root.frameLayoutChildren, [first, hidden, last])
        XCTAssertEqual(root.frameDwindleShares, [0.2, 0.3, 0.5])
    }

    func testNavigationGeometryMapsVisibleFramesToTheirActualWindows() async throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let first = TestWindow.new(id: 1, parent: root)
        let hidden = TestWindow.new(id: 2, parent: root)
        let last = TestWindow.new(id: 3, parent: root)
        hidden.nativeLayoutEligible = false
        let frames = dwindleGeometry(in: workspace)
        XCTAssertNotNil(frames[ObjectIdentifier(first)])
        XCTAssertNil(frames[ObjectIdentifier(hidden)])
        XCTAssertNotNil(frames[ObjectIdentifier(last)])
        XCTAssertTrue(dwindleDirectionalFocusTarget(from: first, direction: .right) === last)
        root.layout = .tiles
        XCTAssertTrue(workspace.usesSpatialFocus)
        _ = first.focusWindow()
        let result = try await NativeTilingCommandScope.$active.withValue(true) {
            try await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        }
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(focus.windowOrNil === last)
    }

    func testStructuralDwindleConversionKeepsConcealedLeavesAndResizeRejectsSafely() async throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let windows = (1...4).map { TestWindow.new(id: UInt32($0), parent: root) }
        for hidden in windows.dropFirst() { hidden.nativeLayoutEligible = false }
        workspace.materializeDwindleTree()
        XCTAssertEqual(Set(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId)), Set([1, 2, 3, 4]))
        XCTAssertTrue(windows.allSatisfy { $0.nodeWorkspace === workspace })
        _ = windows[0].focusWindow()
        let result = try await NativeTilingCommandScope.$active.withValue(true) {
            try await parseCommand("resize width +20").cmdOrDie.run(.defaultEnv, .emptyStdin)
        }
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.joined().contains("concealed siblings"))
        XCTAssertTrue(windows.dropFirst().allSatisfy { !$0.nativeLayoutEligible })
    }

    func testEmptyNestedGroupDoesNotConsumePaneOrLoseMasterIdentity() {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let group = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: 0)
        let a = TestWindow.new(id: 1, parent: group)
        let b = TestWindow.new(id: 2, parent: group)
        let other = TestWindow.new(id: 3, parent: root)
        workspace.arrangement = .master
        workspace.masterGroupIndex = 0
        a.nativeLayoutEligible = false
        b.nativeLayoutEligible = false
        XCTAssertEqual(workspace.workspaceLayoutUnits, [other])
        workspace.normalizeMasterLayout()
        _ = workspace.masterGroupIndex
        a.nativeLayoutEligible = true
        XCTAssertEqual(workspace.workspaceLayoutUnits, [group, other])
        XCTAssertTrue(workspace.workspaceLayoutUnits[workspace.masterGroupIndex] === group)
        XCTAssertEqual(group.children, [a, b])
    }

    func testPersistenceKeepsConcealedMasterIdentityInsteadOfTemporaryVisibleFallback() {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let windows = (1...3).map { TestWindow.new(id: UInt32($0), parent: root) }
        for window in windows {
            window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
                launchDate: Date(timeIntervalSince1970: 1), title: "\(window.windowId)")
        }
        workspace.arrangement = .master
        workspace.masterGroupIndex = 2
        windows[2].nativeLayoutEligible = false
        XCTAssertEqual(workspace.masterGroupIndex, 1) // Temporary visible fallback.
        let record = NativePersistedLayout(workspace)
        XCTAssertEqual(record.masterIndex, 2)
        let store = NativeLayoutPersistence(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertTrue(store.restore(record, to: workspace))
        XCTAssertEqual(workspace.nativePersistentMasterGroupIndex, 2)
        windows[2].nativeLayoutEligible = true
        XCTAssertEqual(workspace.masterGroupIndex, 2)
        XCTAssertTrue(workspace.workspaceLayoutUnits[2] === windows[2])
    }

    func testSharedLayoutDoesNotWriteIneligibleWindowAndPreservesFloatingFrame() async throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let visible = TestWindow.new(id: 1, parent: root)
        let hidden = TestWindow.new(id: 2, parent: root)
        hidden.nativeLayoutEligible = false
        let original = Rect(topLeftX: 20, topLeftY: 50, width: 300, height: 400)
        let floating = TestWindow.new(id: 3, parent: workspace, rect: original)
        try await workspace.layoutWorkspace()
        XCTAssertNotNil(visible.lastAppliedLayoutPhysicalRect)
        XCTAssertNil(hidden.lastAppliedLayoutPhysicalRect)
        let floatingRect = try await floating.getAxRect()
        XCTAssertEqual(floatingRect, original)
        XCTAssertTrue(hidden.parent === root)
        XCTAssertTrue(floating.parent === workspace)
    }

    func testCommandPolicyRejectsCrossSpaceAndOverlappingLayoutsBeforeReadiness() throws {
        for text in ["focus left", "move right", "resize width +20", "workspace-layout master", "layout floating",
                     "workspace-layout scrolling", "scrolling-center", "scrolling-width next"] {
            let command = try XCTUnwrap(parseCommand(text).unwrap().0)
            XCTAssertTrue(NativeTilingCoordinator.supports(command), text)
        }
        config.windowTabs.enabled = true
        XCTAssertTrue(NativeTilingCoordinator.supports(try XCTUnwrap(parseCommand("layout tabbed").unwrap().0)))
        XCTAssertTrue(NativeTilingCoordinator.supports(try XCTUnwrap(parseCommand("layout accordion").unwrap().0)))
        // Past a display edge the move runs after the fenced command; focus across displays
        // runs outside the fence as navigation.
        XCTAssertTrue(NativeTilingCoordinator.supports(try XCTUnwrap(parseCommand("move --boundaries all-monitors-outer-frame left").unwrap().0)))
        XCTAssertTrue(WorkspaceBackendState.isNativeNavigation(try XCTUnwrap(parseCommand("focus --boundaries all-monitors-outer-frame left").unwrap().0)))
        for text in ["workspace 2", "move-node-to-workspace 2",
                     "focus --boundaries all-monitors-outer-frame left"] {
            let command = try XCTUnwrap(parseCommand(text).unwrap().0)
            XCTAssertFalse(NativeTilingCoordinator.supports(command), text)
        }
    }

    func testRestoreDoesNotBorrowWindowFromAnotherSpaceOrFlattenIncompleteTree() throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let group = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: 0)
        let a = TestWindow.new(id: 1, parent: group)
        let b = TestWindow.new(id: 2, parent: group)
        for window in [a, b] {
            window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
                launchDate: Date(timeIntervalSince1970: 1), title: "\(window.windowId)")
        }
        workspace.arrangement = .master
        let record = NativePersistedLayout(workspace)
        let otherSpace = Workspace.get(byName: "other-space")
        b.bind(to: otherSpace.rootTilingContainer, adaptiveWeight: 1, index: 0)
        let store = NativeLayoutPersistence(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertFalse(store.restore(record, to: workspace))
        XCTAssertTrue(workspace.rootTilingContainer === root)
        XCTAssertTrue(root.children.first === group)
        XCTAssertTrue(b.nodeWorkspace === otherSpace)
        b.bind(to: group, adaptiveWeight: 1, index: 1)
        XCTAssertTrue(store.restore(record, to: workspace))
        let restored = workspace.rootTilingContainer
        XCTAssertFalse(restored === root)
        XCTAssertEqual(restored.layout, record.root.layout)
        let restoredGroup = try XCTUnwrap(restored.children.first as? TilingContainer)
        XCTAssertEqual(restoredGroup.layout, .tiles)
        XCTAssertEqual(restoredGroup.children, [a, b])
        XCTAssertEqual(workspace.arrangement, .master)
    }

    func testScrollingDesktopWithTabGroupIsRestoredAfterRestart() throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let windows = [TestWindow.new(id: 1, parent: tabs), TestWindow.new(id: 2, parent: tabs), TestWindow.new(id: 3, parent: root)]
        for window in windows {
            window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
                launchDate: Date(timeIntervalSince1970: 1), title: "\(window.windowId)")
        }
        windows[2].scrollingColumnWidth = 0.6
        workspace.arrangement = .scrolling
        let record = NativePersistedLayout(workspace)
        XCTAssertTrue(record.supported)
        workspace.arrangement = .dwindle
        XCTAssertTrue(NativeLayoutPersistence(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            .restore(record, to: workspace))
        XCTAssertEqual(workspace.arrangement, .scrolling)
        XCTAssertEqual((workspace.rootTilingContainer.children.first as? TilingContainer)?.layout, .tabGroup)
        XCTAssertEqual(windows[2].scrollingColumnWidth, 0.6)
    }

    func testNativePersistenceRoundTripProtectsIncompleteSavedTreeFromAutosave() async throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let group = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: 0)
        let a = TestWindow.new(id: 1, parent: group)
        let b = TestWindow.new(id: 2, parent: group)
        for window in [a, b] {
            window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
                launchDate: Date(timeIntervalSince1970: 1), title: "\(window.windowId)")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("native.json")
        let layouts = runtime.workspaceBackend.nativeLayouts
        let first = NativeLayoutPersistence(url: url)
        await first.reconcile(layouts)
        await first.save(layouts)
        XCTAssertNil(first.lastError)
        let original = try Data(contentsOf: url)
        let elsewhere = Workspace.get(byName: "elsewhere")
        b.bind(to: elsewhere.rootTilingContainer, adaptiveWeight: 1, index: 0)
        let second = NativeLayoutPersistence(url: url)
        await second.reconcile(layouts)
        XCTAssertEqual(second.pendingCount, 1)
        await second.save(layouts)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(b.nodeWorkspace === elsewhere)
        b.bind(to: group, adaptiveWeight: 1, index: 1)
        await second.reconcile(layouts)
        XCTAssertEqual(second.pendingCount, 0)
        let restoredGroup = try XCTUnwrap(workspace.rootTilingContainer.children.first as? TilingContainer)
        XCTAssertEqual(restoredGroup.children, [a, b])
        XCTAssertEqual(restoredGroup.layout, .tiles)
    }

    func testUnmatchedDesktopKeepsItsArrangementAndIsSavedAgainAfterGrace() async throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let window = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)
        window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
            launchDate: Date(timeIntervalSince1970: 1), title: "before reboot")
        workspace.transitionArrangement(to: .scrolling)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("native.json")
        let layouts = runtime.workspaceBackend.nativeLayouts
        let first = NativeLayoutPersistence(url: url)
        await first.reconcile(layouts)
        await first.save(layouts)
        // After a reboot: new process, new title, layout reset by the fresh tree.
        window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 500,
            launchDate: Date(timeIntervalSince1970: 2), title: "after reboot")
        workspace.transitionArrangement(to: .dwindle)
        var clock = ContinuousClock.now
        let second = NativeLayoutPersistence(url: url)
        second.now = { clock }
        await second.reconcile(layouts)
        XCTAssertEqual(workspace.arrangement, .scrolling, "The desktop's arrangement survives a restart")
        XCTAssertEqual(second.pendingCount, 1)
        workspace.transitionArrangement(to: .master)
        await second.reconcile(layouts)
        XCTAssertEqual(workspace.arrangement, .master, "The fallback applies once; later choices are the user's")
        clock = clock.advanced(by: .seconds(120))
        await second.reconcile(layouts)
        XCTAssertEqual(second.pendingCount, 0)
        await second.save(layouts)
        struct File: Decodable { let spaces: [String: NativePersistedLayout] }
        let saved = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved.spaces.values.first?.arrangement, .master, "Saving resumes after the grace period")
    }

    func testUnreadableNativePersistenceIsNeverOverwritten() async throws {
        _ = nativeWorkspace()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("native.json")
        let original = Data("{invalid".utf8)
        try original.write(to: url)
        let store = NativeLayoutPersistence(url: url)
        await store.reconcile(runtime.workspaceBackend.nativeLayouts)
        await store.save(runtime.workspaceBackend.nativeLayouts)
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testNativeCommandsRetainNestedGroupsAndRejectHiddenWindowTarget() async throws {
        let workspace = nativeWorkspace()
        let group = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .v, .tiles, index: 0)
        let a = TestWindow.new(id: 1, parent: group)
        let b = TestWindow.new(id: 2, parent: group)
        _ = a.focusWindow()
        let result = try await NativeTilingCommandScope.$active.withValue(true) {
            try await parseCommand("workspace-layout master").cmdOrDie.run(.defaultEnv, .emptyStdin)
        }
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(workspace.arrangement, .master)
        XCTAssertTrue(workspace.rootTilingContainer.children.first === group)
        XCTAssertEqual(group.children, [a, b])
        b.nativeLayoutEligible = false
        let rejected = try await NativeTilingCommandScope.$active.withValue(true) {
            try await parseCommand("resize --window-id 2 width +20").cmdOrDie.run(.defaultEnv, .emptyStdin)
        }
        XCTAssertNotEqual(rejected.exitCode, 0)
        XCTAssertTrue(rejected.stderr.joined().contains("eligible"))
        XCTAssertEqual(group.children, [a, b])
    }
}

@MainActor
final class NativeTabStackingTest: WorkspaceTestCase {
    func testOnlyActiveTabsCoveredBySiblingsAreRaised() throws {
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: "tabs")
        let tabs = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .h, .tabGroup, index: 0)
        let inactive = TestWindow.new(id: 11, parent: tabs)
        let active = TestWindow.new(id: 12, parent: tabs)
        active.markAsMostRecentChild()
        let other = TestWindow.new(id: 13, parent: workspace.rootTilingContainer)
        // TestWindow is not a MacWindow, so check the ordering decision through the ids.
        func covered(_ order: [UInt32]) -> Bool {
            let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            return tabs.allLeafWindowsRecursive.contains { $0 !== active && (position[$0.windowId] ?? .max) < position[active.windowId]! }
        }
        XCTAssertTrue(covered([inactive.windowId, active.windowId, other.windowId]))
        XCTAssertFalse(covered([other.windowId, active.windowId, inactive.windowId]), "Unrelated windows never force a raise")
        XCTAssertTrue(nativeTabsToRaise(in: workspace, position: [11: 0, 12: 1]).isEmpty, "Only real app windows are raised")
    }
}
