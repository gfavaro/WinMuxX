@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class WorkspaceSidebarPanelLifecycleTest: WorkspaceTestCase {
    func testRepeatedExpansionKeepsRevealAndBackingResize() throws {
        config.workspaceSidebar.enabled = false // Offscreen fixture only.
        defer { WorkspaceSidebarPanel.refreshAll(on: []) }
        let screen = monitor(x: 3840)
        WorkspaceSidebarPanel.refreshAll(on: [screen])
        let panel = try XCTUnwrap(WorkspaceSidebarPanel.panel(for: workspaceSidebarMonitorScopeId(for: screen)))
        let revealed = expectation(forNotification: workspaceSidebarWillExpandNotification, object: panel)
        revealed.expectedFulfillmentCount = 1
        revealed.assertForOverFulfill = true
        panel.expandSidebar(to: 240)
        let resize = try XCTUnwrap(panel.pendingBackingResize)
        panel.expandSidebar(to: 240)
        XCTAssertTrue(panel.pendingBackingResize === resize)
        XCTAssertFalse(resize.isCancelled)
        XCTAssertEqual(panel.viewModel.workspaceSidebarVisibleWidth, 240)
        wait(for: [revealed], timeout: 1)
    }

    func testHoverWaitsForDwellAndExitCancelsReveal() throws {
        config.workspaceSidebar.enabled = false // Offscreen fixture only.
        config.workspaceSidebar.autoHide = true
        defer { WorkspaceSidebarPanel.refreshAll(on: []) }
        let screen = monitor(x: 3840)
        WorkspaceSidebarPanel.refreshAll(on: [screen])
        let panel = try XCTUnwrap(WorkspaceSidebarPanel.panel(for: workspaceSidebarMonitorScopeId(for: screen)))
        panel.leftMousePressStartedInsideSidebar = true // Independent of a user's live mouse button.
        panel.handleHoverEnter(expandedWidth: 240, collapsedWidth: 0)
        XCTAssertEqual(panel.viewModel.workspaceSidebarVisibleWidth, 0)
        XCTAssertFalse(panel.viewModel.isWorkspaceSidebarExpanded)
        XCTAssertNotNil(panel.pendingExpand)
        let pending = panel.pendingExpand
        panel.handleHoverExit(collapsedWidth: 0)
        XCTAssertTrue(pending?.isCancelled == true)
        XCTAssertNil(panel.pendingExpand)
        XCTAssertEqual(panel.viewModel.workspaceSidebarVisibleWidth, 0)
    }

    func testObsoleteMonitorPanelsAreReleasedAndRecreatedWithoutReplacingActivePanels() async throws {
        config.workspaceSidebar.enabled = false // Never show native panels on the desktop.
        defer { WorkspaceSidebarPanel.refreshAll(on: []) }
        let first = monitor(x: 0), second = monitor(x: 1920)
        let firstId = workspaceSidebarMonitorScopeId(for: first)
        let secondId = workspaceSidebarMonitorScopeId(for: second)
        WorkspaceSidebarPanel.refreshAll(on: [first, second])
        let active = try XCTUnwrap(WorkspaceSidebarPanel.panel(for: firstId))
        weak var obsolete = WorkspaceSidebarPanel.panel(for: secondId)
        XCTAssertNotNil(obsolete)

        autoreleasepool { WorkspaceSidebarPanel.refreshAll(on: [first]) }
        XCTAssertTrue(WorkspaceSidebarPanel.panel(for: firstId) === active)
        XCTAssertNil(WorkspaceSidebarPanel.panel(for: secondId))
        // AppKit/SwiftUI may defer the final native view release until the next
        // main-queue turn. Observe that completion rather than sleeping.
        let released = expectation(description: "Retired panel released")
        DispatchQueue.main.async {
            XCTAssertNil(obsolete)
            released.fulfill()
        }
        await fulfillment(of: [released], timeout: 2)

        WorkspaceSidebarPanel.refreshAll(on: [first, second])
        XCTAssertTrue(WorkspaceSidebarPanel.panel(for: firstId) === active)
        XCTAssertNotNil(WorkspaceSidebarPanel.panel(for: secondId))
        WorkspaceSidebarPanel.refreshAll(on: [])
        XCTAssertNil(WorkspaceSidebarPanel.panel(for: firstId))
        XCTAssertNil(WorkspaceSidebarPanel.panel(for: secondId))
    }

    func testRetirementCancelsOwnedResourcesAndRejectsLateReopening() throws {
        config.workspaceSidebar.enabled = false
        defer { WorkspaceSidebarPanel.refreshAll(on: []) }
        let screen = monitor(x: 3840)
        WorkspaceSidebarPanel.refreshAll(on: [screen])
        let panel = try XCTUnwrap(WorkspaceSidebarPanel.panel(for: workspaceSidebarMonitorScopeId(for: screen)))
        let work = (0..<4).map { _ in DispatchWorkItem {} }
        panel.pendingBackingResize = work[0]
        panel.pendingExpand = work[1]
        panel.pendingCollapse = work[2]
        panel.pendingCollapseFinalize = work[3]
        panel.inlineTextEditingActive = true
        WorkspaceSidebarPanel.activeInlineTextEditingPanel = panel
        panel.commandExpansionLocksCollapse = true
        panel.bufferedCommandSidebarSearchKeys = [.text("query")]
        panel.inlineTextEditingCancel = { XCTFail("Retiring must not commit or cancel user edits through callbacks") }
        panel.inlineTextEditingKeyDown = { _ in XCTFail("Retired editor callback") }
        panel.commandMouseUnlockMonitors = [try XCTUnwrap(NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { $0 })]
        panel.inlineTextEditingEventMonitors = [try XCTUnwrap(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { $0 })]
        XCTAssertFalse(panel.menuTrackingObservers.isEmpty)

        WorkspaceSidebarPanel.refreshAll(on: [])
        XCTAssertTrue(panel.isRetired)
        XCTAssertTrue(work.allSatisfy(\.isCancelled))
        XCTAssertNil(panel.inlineTextEditingCancel)
        XCTAssertNil(panel.inlineTextEditingKeyDown)
        XCTAssertNil(WorkspaceSidebarPanel.activeInlineTextEditingPanel)
        XCTAssertTrue(panel.commandMouseUnlockMonitors.isEmpty)
        XCTAssertTrue(panel.inlineTextEditingEventMonitors.isEmpty)
        XCTAssertTrue(panel.menuTrackingObservers.isEmpty)
        XCTAssertTrue(panel.bufferedCommandSidebarSearchKeys.isEmpty)
        XCTAssertNil(panel.hostingView.rootView)
        XCTAssertNil(panel.contentView)

        panel.retire() // Disposal is idempotent even while a caller retains the panel.
        panel.refresh(on: screen)
        panel.expandSidebar(to: 300)
        panel.beginInlineTextEditing()
        panel.prepareForInlineTextEditing()
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.inlineTextEditingActive)
        XCTAssertEqual(panel.viewModel.workspaceSidebarVisibleWidth, 0)
        XCTAssertNil(WorkspaceSidebarPanel.activeInlineTextEditingPanel)
    }

    private func monitor(x: CGFloat) -> WorkspaceSidebarDragTestMonitor {
        let rect = Rect(topLeftX: x, topLeftY: 0, width: 1920, height: 1080)
        return WorkspaceSidebarDragTestMonitor(monitorAppKitNsScreenScreensId: 1,
            name: "Test", rect: rect, visibleRect: rect, isMain: x == 0)
    }
}
