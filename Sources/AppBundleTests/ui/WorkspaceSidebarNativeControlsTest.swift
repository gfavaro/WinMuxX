@testable import AppBundle
import AppKit
import SwiftUI
import XCTest

@MainActor
final class WorkspaceSidebarNativeControlsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testProjectMenuKeepsDuplicateNamesDistinctAndPreservesManagementActions() throws {
        let first = WorkspaceSidebarProjectViewModel(id: createWorkspaceProject().id, displayName: "Work", colorHex: nil)
        let second = WorkspaceSidebarProjectViewModel(id: createWorkspaceProject().id, displayName: "Work", colorHex: "#7BA3C9")
        var selected: WorkspaceProjectId?
        var renamed: WorkspaceProjectId?
        var deleted: WorkspaceProjectId?
        var colorProject: WorkspaceProjectId?
        var colorHex: String?
        let view = WorkspaceSidebarNativeProjectMenu(
            projects: [first, second], selectedProjectId: second.id, title: "Work",
            isMenuOpen: .constant(false),
            onSelect: { selected = $0 }, onRename: { renamed = $0.id },
            onSetColor: { colorProject = $0.id; colorHex = $1 }, onDelete: { deleted = $0.id }
        )
        let coordinator = view.makeCoordinator()
        let menu = coordinator.makeMenu()
        let firstItem = try XCTUnwrap(menu.item(at: 1) as? WorkspaceSidebarProjectMenuItem)
        let secondItem = try XCTUnwrap(menu.item(at: 2) as? WorkspaceSidebarProjectMenuItem)
        XCTAssertEqual(firstItem.state, .off)
        XCTAssertEqual(secondItem.state, .on)
        firstItem.performAction(nil)
        XCTAssertEqual(selected, first.id)
        secondItem.performAction(nil)
        XCTAssertEqual(selected, second.id)

        let management = try XCTUnwrap(menu.item(withTitle: "Manage Projects")?.submenu?.item(at: 1)?.submenu)
        try XCTUnwrap(management.item(withTitle: "Rename Project") as? WorkspaceSidebarProjectMenuItem).performAction(nil)
        XCTAssertEqual(renamed, second.id)
        let colors = try XCTUnwrap(management.item(withTitle: "Color")?.submenu)
        let blue = try XCTUnwrap(colors.item(withTitle: "Blue") as? WorkspaceSidebarProjectMenuItem)
        XCTAssertEqual(blue.state, .on)
        blue.performAction(nil)
        XCTAssertEqual(colorProject, second.id)
        XCTAssertEqual(colorHex, "#7BA3C9")
        try XCTUnwrap(colors.item(withTitle: "Auto") as? WorkspaceSidebarProjectMenuItem).performAction(nil)
        XCTAssertNil(colorHex)
        let delete = try XCTUnwrap(management.item(withTitle: "Delete Project") as? WorkspaceSidebarProjectMenuItem)
        XCTAssertTrue(delete.isEnabled)
        delete.performAction(nil)
        XCTAssertEqual(deleted, second.id)
    }

    func testDefaultProjectDeletionRemainsDisabled() throws {
        let project = WorkspaceSidebarProjectViewModel(id: workspaceProjectDefaultId, displayName: "Default", colorHex: nil)
        let view = WorkspaceSidebarNativeProjectMenu(
            projects: [project], selectedProjectId: project.id, title: project.displayName,
            isMenuOpen: .constant(false), onSelect: { _ in }, onRename: { _ in },
            onSetColor: { _, _ in }, onDelete: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let menu = coordinator.makeMenu()
        let delete = try XCTUnwrap(menu.item(withTitle: "Manage Projects")?.submenu?.item(at: 0)?.submenu?.item(withTitle: "Delete Project"))
        XCTAssertFalse(delete.isEnabled)
    }

    func testSegmentSelectionUsesCurrentScopeIdsAndIgnoresNoSelection() {
        let scopes = [workspaceSidebarDefaultScopeId, workspaceSidebarFocusedScopeId].map {
            WorkspaceSidebarMonitorScopeViewModel(id: $0, displayName: $0, subtitle: nil, systemImageName: "display", isFocusedMonitor: false)
        }
        var selected: String?
        let coordinator = WorkspaceSidebarScopeSegmentedControl(
            scopes: scopes, selectedScopeId: nil, onSelect: { selected = $0 }
        ).makeCoordinator()
        let control = NSSegmentedControl()
        control.segmentCount = 2
        control.selectedSegment = 1
        coordinator.selectScope(control)
        XCTAssertEqual(selected, workspaceSidebarFocusedScopeId)
        coordinator.parent = WorkspaceSidebarScopeSegmentedControl(
            scopes: Array(scopes.reversed()), selectedScopeId: nil, onSelect: { selected = $0 }
        )
        coordinator.selectScope(control)
        XCTAssertEqual(selected, workspaceSidebarDefaultScopeId)
        selected = nil
        control.selectedSegment = -1
        coordinator.selectScope(control)
        XCTAssertNil(selected)
    }

    func testRenameSupportsNativeReplacementAndCommitsOnlyAfterComposition() {
        var name = "Project Alpha"
        var committed = false
        var cancelled = false
        let coordinator = WorkspaceSidebarProjectRenameTextField.Coordinator(
            text: Binding(get: { name }, set: { name = $0 }),
            onCommit: { committed = true }, onCancel: { cancelled = true }, onPanelReady: { _ in }
        )
        let field = NSTextField()
        let editor = NSTextView()
        editor.string = name
        XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: #selector(NSTextView.paste(_:))))
        editor.selectedRange = NSRange(location: 8, length: 5)
        editor.insertText("Beta", replacementRange: editor.selectedRange)
        field.stringValue = editor.string
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(name, "Project Beta")
        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(committed)
        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertTrue(cancelled)
        committed = false
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertFalse(committed)
    }
}
