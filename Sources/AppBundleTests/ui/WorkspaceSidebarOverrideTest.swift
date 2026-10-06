@testable import AppBundle
import SwiftUI
import AppKit
import Common
import XCTest

@MainActor
final class WorkspaceSidebarOverrideTest: XCTestCase {
    override func setUp() {
        super.setUp()
        // SwiftUI lazily creates its accessibility nodes only when requested.
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    }

    override func tearDown() {
        NSApplication.shared.accessibilitySetValue(false, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        super.tearDown()
    }

    private func render<Content: View>(_ view: Content, size: CGSize) -> (NSWindow, NSHostingView<Content>) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return (window, host)
    }

    private func accessibilityButtons(_ element: AnyObject) -> [AnyObject] {
        // SwiftUI nodes implement the selectors without declaring protocol conformance.
        var result: [AnyObject] = element.accessibilityRole?() == .button ? [element] : []
        let children = element.accessibilityChildren?() ?? []
        for child in children {
            result += accessibilityButtons(child as AnyObject)
        }
        return result
    }

    func testRenderedCompactOverrideFitsNarrowRailsAndPerformsAction() throws {
        for railWidth: CGFloat in [33, 44, 57] {
            var count = 0
            let width = WorkspaceSidebarCompactMetrics(width: railWidth).sectionWidth
            let (window, host) = render(WorkspaceSidebarInUseOverrideOverlay(
                text: "In use on External Display", isCompact: true, onOverride: { count += 1 }
            ).frame(width: width, height: 44), size: CGSize(width: width, height: 44))
            defer { window.close() }
            let button = try XCTUnwrap(accessibilityButtons(host).first { ($0.accessibilityLabel?() ?? $0.accessibilityTitle?()) == "Override" })
            let size = try XCTUnwrap(button.accessibilityFrame?()).size
            XCTAssertLessThanOrEqual(size.width, width, "Button overflows compact rail \(railWidth)")
            XCTAssertGreaterThanOrEqual(size.height, 28)
            XCTAssertEqual(button.accessibilityPerformPress?(), true)
            XCTAssertEqual(count, 1)
        }
    }

    func testRenderedExpandedConfirmationOffersExplicitCancel() throws {
        var overrides = 0
        var cancels = 0
        let (window, host) = render(WorkspaceSidebarInUseOverrideOverlay(
            text: "In use on External Display", onOverride: { overrides += 1 }, onCancel: { cancels += 1 }
        ).frame(width: 240, height: 100), size: CGSize(width: 240, height: 100))
        defer { window.close() }
        let buttons = accessibilityButtons(host)
        let cancel = try XCTUnwrap(buttons.first { ($0.accessibilityLabel?() ?? $0.accessibilityTitle?()) == "Cancel" })
        XCTAssertEqual(cancel.accessibilityPerformPress?(), true)
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(overrides, 0)
    }

    func testCompactAndExpandedClicksRequireExplicitOverride() throws {
        let item = WorkspaceSidebarWindowViewModel(windowId: 10, workspaceName: "remote",
            appName: "Finder", appBundleId: "com.apple.finder", appBundlePath: nil,
            title: "Example", isFocused: false)
        var layout = WorkspaceSidebarConfiguration.empty
        layout.collapsedWidth = 44
        layout.expandedWidth = 240
        let workspace = WorkspaceSidebarWorkspaceViewModel(
            name: "remote", projectId: workspaceProjectDefaultId, displayName: "Remote",
            sidebarLabel: "Remote", isGeneratedName: false,
            monitorScopeId: "monitor:1920.0,0.0", monitorName: "External Display",
            isFocused: false, isVisible: true, items: [WorkspaceSidebarItemViewModel(kind: .window(item))])
        for progress: CGFloat in [0, 1] {
            var pending: String?
            var actions: [WorkspaceSidebarAction] = []
            let section = WorkspaceSidebarWorkspaceSection(
                workspace: workspace, dragPreview: nil, expansionProgress: progress,
                layout: layout, emitsDropTarget: false, isFromOtherDisplay: false,
                isInUseOnOtherDisplay: true, isOnFocusedMonitor: false,
                allowsWorkspaceActivation: true, isPinnedActiveWorkspace: false,
                isActiveOnTargetMonitor: false, projectContextLabel: nil, projectContextColor: nil,
                renamingWorkspaceName: .constant(nil), renamingWorkspaceText: .constant(""),
                onBeginRenameWorkspace: {}, onCommitRenameWorkspace: {}, onCancelRenameWorkspace: {},
                selectedSearchTarget: nil, isSearchFiltering: false,
                activeInUseOverrideWorkspaceName: Binding(get: { pending }, set: { pending = $0 }),
                actions: WorkspaceSidebarActions(send: { actions.append($0) }))
            section.handleSectionClick()
            XCTAssertEqual(pending, workspace.name)
            XCTAssertTrue(actions.isEmpty, "A click must request confirmation before activating or swapping")
            XCTAssertEqual(section.inUseOverrideText, "In use on External Display")
            XCTAssertEqual(section.overrideConfirmation.isCompact, progress == 0)
            if progress == 1 {
                XCTAssertEqual(section.sectionMinHeight, workspaceSidebarInUseOverrideEmptySectionMinHeight)
                let (window, host) = render(section, size: CGSize(width: 240, height: 121))
                defer { window.close() }
                let override = try XCTUnwrap(accessibilityButtons(host).first { $0.accessibilityLabel?() == "Override" })
                let frame = try XCTUnwrap(override.accessibilityFrame?())
                XCTAssertTrue(window.accessibilityFrame().contains(frame), "Confirmation button must remain inside the section's hit area")
                XCTAssertEqual(override.accessibilityPerformPress?(), true)
                XCTAssertNil(pending)
                XCTAssertEqual(actions, [.overrideWorkspaceInUse(workspace.name)])
            }
        }
    }
}

@MainActor
final class WorkspaceSidebarOverrideSizeRegressionTest: XCTestCase {
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
