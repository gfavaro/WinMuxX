@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class RuntimePerformanceScenarioTest: WorkspaceTestCase {
    func testWarmOverlayLifecycleAndWorkspaceNavigationReleaseOwnedResources() async throws {
        config.workspaceSidebar.enabled = false
        config.persistentWorkspaces = ["perf-a", "perf-b"]
        Workspace.reconcileWorkspaceState()
        let first = Workspace.get(byName: "perf-a"), second = Workspace.get(byName: "perf-b")
        var installations = 0, removals = 0
        let palette = SwitcherPalettePanel(loadItems: { [] }, nativePresentation: false,
            observeOutsideClicks: { _ in installations += 1; return [NSObject()] },
            removeMonitor: { _ in removals += 1 })
        WorkspaceSidebarPanel.refreshAll(on: [mainMonitor])
        defer { WorkspaceSidebarPanel.refreshAll(on: []) }
        let sidebar = try XCTUnwrap(WorkspaceSidebarPanel.panel(for: workspaceSidebarMonitorScopeId(for: mainMonitor)))
        for iteration in 0..<120 {
            await palette.show()
            palette.dismiss()
            sidebar.expandSidebar(to: 240)
            sidebar.cancelExpansionWork()
            sidebar.resetHiddenSidebarState()
            sidebar.viewModel.isWorkspaceSidebarExpanded = false
            if iteration >= 20 { _ = (iteration.isMultiple(of: 2) ? first : second).focusWorkspace() }
            XCTAssertNil(sidebar.pendingBackingResize)
            XCTAssertNil(sidebar.pendingExpand)
            XCTAssertEqual(palette.ownedMonitorCount, 0)
        }
        XCTAssertEqual(installations, 120)
        XCTAssertEqual(removals, installations)
        XCTAssertTrue(sidebar.commandMouseUnlockMonitors.isEmpty)
        XCTAssertTrue(sidebar.inlineTextEditingEventMonitors.isEmpty)
        print("RUNTIME_LIFECYCLE_SCENARIO warmup=20 measured=100 monitor_balance=0 pending_work=0")
    }
}
