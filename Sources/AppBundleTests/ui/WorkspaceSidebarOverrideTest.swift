@testable import AppBundle
import AppKit
import Common
import SwiftUI
import XCTest

@MainActor
final class WorkspaceSidebarOverrideTest: XCTestCase {
    func testConfirmationTracksCompactExpandedAndSplitWidths() {
        for collapsed: CGFloat in [36, 44, 56, 80, 120] {
            for expanded: CGFloat in [160, 240, 280, 420] {
                var view = fixture(collapsed: collapsed, expanded: expanded, visible: collapsed)
                XCTAssertEqual(state(view).workspaceName, "remote")
                XCTAssertFalse(state(view).locksCollapse)
                view = fixture(collapsed: collapsed, expanded: expanded, visible: expanded)
                XCTAssertTrue(state(view).locksCollapse)
                view = fixture(collapsed: collapsed, expanded: expanded, visible: expanded * 2)
                XCTAssertTrue(state(view).locksCollapse)
                view = fixture(collapsed: collapsed, expanded: expanded, visible: collapsed)
                XCTAssertFalse(state(view).locksCollapse)
            }
        }
    }

    func testSearchAndMonitorFilterReleaseHiddenConfirmation() {
        var view = fixture()
        XCTAssertTrue(state(view).locksCollapse)
        XCTAssertNil(state(view, query: "does-not-match").workspaceName)
        XCTAssertFalse(state(view, query: "does-not-match").locksCollapse)
        view = fixture()
        var snapshot = view.snapshot
        snapshot.selectedMonitorScopeId = "monitor:0.0,0.0"
        view = fixture(snapshot: snapshot)
        XCTAssertNil(state(view).workspaceName)
        XCTAssertFalse(state(view).locksCollapse)
    }

    func testRemovedWorkspaceAndProjectBrowseReleaseConfirmation() {
        var view = fixture()
        var snapshot = view.snapshot
        snapshot.workspaces = []
        view = fixture(snapshot: snapshot)
        XCTAssertNil(state(view).workspaceName)
        XCTAssertFalse(state(view).locksCollapse)
        view = fixture()
        XCTAssertNil(state(view, browseMode: .split(otherProjectId: "other")).workspaceName)
        XCTAssertFalse(state(view, browseMode: .split(otherProjectId: "other")).locksCollapse)
    }

    func testWorkspaceMovingToTargetMonitorReleasesConfirmation() {
        var snapshot = fixture().snapshot
        snapshot.targetMonitorScopeId = "monitor:1920.0,0.0"
        XCTAssertNil(state(fixture(snapshot: snapshot)).workspaceName)
        XCTAssertFalse(state(fixture(snapshot: snapshot)).locksCollapse)
    }

    func testDismissedConfirmationReleasesCollapseLock() {
        let view = fixture()
        XCTAssertTrue(state(view).locksCollapse)
        XCTAssertNil(state(view, name: nil).workspaceName)
        XCTAssertFalse(state(view, name: nil).locksCollapse)
    }

    func testOverlayIntrinsicControlsFitCompactAndExpandedWidths() {
        let compact = NSHostingView(rootView: WorkspaceSidebarInUseOverrideOverlay(
            text: "In use on an ultrawide external display", isCompact: true, onOverride: {}
        ).fixedSize())
        compact.layoutSubtreeIfNeeded()
        for width: CGFloat in [36, 44, 56, 80, 120] {
            let availableWidth = width - 2 * workspaceSidebarCompactRailHorizontalInset
            XCTAssertLessThanOrEqual(compact.fittingSize.width, availableWidth, "Compact rail \(width)")
            XCTAssertLessThanOrEqual(compact.fittingSize.height, 38)
        }
        // The expanded label can wrap; its buttons must fit even at the narrowest supported test width.
        let expanded = NSHostingView(rootView: WorkspaceSidebarInUseOverrideOverlay(
            text: "In use", onOverride: {}, onCancel: {}
        ).fixedSize())
        expanded.layoutSubtreeIfNeeded()
        for width: CGFloat in [160, 240, 280, 420] {
            XCTAssertLessThanOrEqual(expanded.fittingSize.width, width - 24)
            XCTAssertLessThanOrEqual(expanded.fittingSize.height, workspaceSidebarInUseOverrideEmptySectionMinHeight)
            let longLabel = NSHostingView(rootView: WorkspaceSidebarInUseOverrideOverlay(
                text: "In use on a very long ultrawide external monitor name", onOverride: {}, onCancel: {}
            ).frame(width: width - 24).fixedSize(horizontal: false, vertical: true))
            longLabel.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(longLabel.fittingSize.height, workspaceSidebarInUseOverrideEmptySectionMinHeight,
                                     "Expanded rail \(width) with a long monitor name")
        }
    }

    private func state(_ view: WorkspaceSidebarView, query: String = "", browseMode: WorkspaceSidebarBrowseMode = .activeProject,
                       name: String? = "remote") -> WorkspaceSidebarOverrideConfirmationState {
        workspaceSidebarOverrideConfirmationState(snapshot: view.snapshot, browseMode: browseMode, query: query, requestedWorkspaceName: name)
    }

    private func fixture(collapsed: CGFloat = 44, expanded: CGFloat = 280, visible: CGFloat = 280,
                         snapshot: WorkspaceSidebarSnapshot? = nil) -> WorkspaceSidebarView {
        var model = snapshot ?? .empty
        if snapshot == nil {
            model.activeProjectId = workspaceProjectDefaultId
            model.projects = [WorkspaceSidebarProjectViewModel(id: workspaceProjectDefaultId, displayName: "Default", colorHex: nil)]
            model.selectedMonitorScopeId = workspaceSidebarDefaultScopeId
            model.targetMonitorScopeId = "monitor:0.0,0.0"
            model.configuration.collapsedWidth = collapsed
            model.configuration.expandedWidth = expanded
            model.visibleWidth = visible
            model.workspaces = [WorkspaceSidebarWorkspaceViewModel(
                name: "remote", projectId: workspaceProjectDefaultId, displayName: "Remote", sidebarLabel: "",
                isGeneratedName: false, monitorScopeId: "monitor:1920.0,0.0", monitorName: "External",
                isFocused: false, isVisible: true, items: []
            )]
        }
        return WorkspaceSidebarView(snapshot: model)
    }
}
