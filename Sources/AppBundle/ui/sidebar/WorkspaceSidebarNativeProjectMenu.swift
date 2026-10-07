import AppKit
import SwiftUI

@MainActor
final class WorkspaceSidebarProjectMenuItem: NSMenuItem {
    var handler: (@MainActor () -> Void)?

    @objc func performAction(_ sender: Any?) { handler?() }
}

struct WorkspaceSidebarNativeProjectMenu: NSViewRepresentable {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId?
    let title: String
    @Binding var isMenuOpen: Bool
    let onSelect: (WorkspaceProjectId) -> Void
    let onRename: (WorkspaceSidebarProjectViewModel) -> Void
    let onSetColor: (WorkspaceSidebarProjectViewModel, String?) -> Void
    let onDelete: (WorkspaceSidebarProjectViewModel) -> Void

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12)
        button.setAccessibilityLabel("Projects")
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.button = button
        coordinator.appearance = context.environment.workspaceSidebarAppearance
        button.appearance = NSAppearance(named: coordinator.appearance == .custom || context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        if coordinator.isTracking {
            if !isMenuOpen { button.menu?.cancelTrackingWithoutAnimation() }
            return
        }
        button.menu = coordinator.makeMenu()
        button.isEnabled = !projects.isEmpty
    }

    static func dismantleNSView(_ button: NSPopUpButton, coordinator: Coordinator) {
        button.menu?.cancelTrackingWithoutAnimation()
        button.menu?.delegate = nil
        coordinator.button = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: WorkspaceSidebarNativeProjectMenu
        var appearance: WorkspaceSidebarAppearance = .system
        weak var button: NSPopUpButton?
        weak var capturedPanel: WorkspaceSidebarPanel?
        var restoresKeyCapture = false
        var isTracking = false

        init(parent: WorkspaceSidebarNativeProjectMenu) { self.parent = parent }

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            // The first item supplies the pull-down button's title.
            menu.addItem(NSMenuItem(title: parent.title, action: nil, keyEquivalent: ""))
            for project in parent.projects {
                let item = action(project.displayName) { [weak self] in self?.parent.onSelect(project.id) }
                item.state = project.id == parent.selectedProjectId ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let management = NSMenuItem(title: "Manage Projects", action: nil, keyEquivalent: "")
            let projectsMenu = NSMenu()
            projectsMenu.autoenablesItems = false
            for project in parent.projects {
                let item = NSMenuItem(title: project.displayName, action: nil, keyEquivalent: "")
                item.submenu = managementMenu(for: project)
                projectsMenu.addItem(item)
            }
            management.submenu = projectsMenu
            menu.addItem(management)
            return menu
        }

        private func managementMenu(for project: WorkspaceSidebarProjectViewModel) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(action("Rename Project") { [weak self] in self?.parent.onRename(project) })
            let color = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
            let colors = NSMenu()
            colors.autoenablesItems = false
            let selectedHex = project.colorHex.flatMap(normalizedWorkspaceSidebarColorHex)
            let automatic = action("Auto") { [weak self] in self?.parent.onSetColor(project, nil) }
            automatic.state = selectedHex == nil ? .on : .off
            automatic.image = workspaceSidebarAutomaticColorSwatchImage(isSelected: selectedHex == nil, appearance: appearance)
            colors.addItem(automatic)
            colors.addItem(.separator())
            for preset in workspaceSidebarProjectColorPresets {
                let item = action(preset.name) { [weak self] in self?.parent.onSetColor(project, preset.hex) }
                item.state = selectedHex == preset.hex ? .on : .off
                item.image = workspaceSidebarProjectColorSwatchImage(hex: preset.hex, isSelected: selectedHex == preset.hex, appearance: appearance)
                colors.addItem(item)
            }
            color.submenu = colors
            menu.addItem(color)
            menu.addItem(.separator())
            let delete = action("Delete Project") { [weak self] in self?.parent.onDelete(project) }
            delete.isEnabled = canDeleteWorkspaceProject(project.id)
            menu.addItem(delete)
            return menu
        }

        private func action(_ title: String, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
            let item = WorkspaceSidebarProjectMenuItem(title: title, action: #selector(WorkspaceSidebarProjectMenuItem.performAction(_:)), keyEquivalent: "")
            item.target = item
            item.handler = handler
            return item
        }

        func menuWillOpen(_ menu: NSMenu) {
            isTracking = true
            parent.isMenuOpen = true
            capturedPanel = button?.window as? WorkspaceSidebarPanel
            restoresKeyCapture = capturedPanel?.inlineTextEditingKeyEventTap != nil
            capturedPanel?.removeInlineTextEditingKeyEventTap()
        }

        func menuDidClose(_ menu: NSMenu) {
            isTracking = false
            if restoresKeyCapture, let panel = capturedPanel, panel.inlineTextEditingActive,
               panel.inlineTextEditingKeyDown != nil {
                panel.installInlineTextEditingKeyEventTap()
            }
            restoresKeyCapture = false
            capturedPanel = nil
            parent.isMenuOpen = false
        }
    }
}
