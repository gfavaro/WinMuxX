import AppKit
import Common
import SwiftUI

// MARK: - Monitor Selector

struct WorkspaceSidebarMonitorSelector: View {
    let scopes: [WorkspaceSidebarMonitorScopeViewModel]
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedScopeId: String
    let activeProjectId: WorkspaceProjectId
    let browsedProjectId: WorkspaceProjectId?
    let expansionProgress: CGFloat
    let sectionWidth: CGFloat
    var onSelectScope: (String) -> Void = { selectWorkspaceSidebarMonitorScope($0) }
    var onSelectProject: (WorkspaceProjectId?) -> Void = { _ in }
    var onRenameProject: (WorkspaceSidebarProjectViewModel) -> Void = { _ in }
    @Binding var renamingProjectId: WorkspaceProjectId?
    @Binding var renamingProjectText: String
    var onCommitRenameProject: @MainActor @Sendable () -> Void = {}
    var onCancelRenameProject: @MainActor @Sendable () -> Void = {}
    var onSetProjectColor: (WorkspaceSidebarProjectViewModel, String?) -> Void = { _, _ in }
    var onDeleteProject: (WorkspaceSidebarProjectViewModel) -> Void = { _ in }
    var measuring = false

    @State private var isProjectMenuOpen = false
    private var projectPopupWidth: CGFloat {
        let names = browsableProjects.map(\.displayName) + ["Other Projects"]
        let maxTextWidth = names.map {
            ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
        }.max() ?? 0
        return max(ceil(maxTextWidth) + 50, 116)
    }
    private var quickScopes: [WorkspaceSidebarMonitorScopeViewModel] {
        var result = [
            scopes.first { $0.id == workspaceSidebarDefaultScopeId }
                ?? WorkspaceSidebarMonitorScopeViewModel(
                    id: workspaceSidebarDefaultScopeId,
                    displayName: "Default",
                    subtitle: nil,
                    systemImageName: "display",
                    isFocusedMonitor: false
                ),
        ]
        if let focusedScope = scopes.first(where: { $0.id == workspaceSidebarFocusedScopeId }) {
            result.append(focusedScope)
        }
        return result
    }

    private var selectedProject: WorkspaceSidebarProjectViewModel? {
        guard let browsedProjectId else { return nil }
        return projects.first { $0.id == browsedProjectId }
    }

    private var browsableProjects: [WorkspaceSidebarProjectViewModel] {
        projects.filter { $0.id != activeProjectId }
    }

    private var scopeControlWidth: CGFloat {
        quickScopes.reduce(0) { width, scope in
            let label = scope.id == workspaceSidebarFocusedScopeId ? "Focus" : scope.displayName
            return width + ceil((label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width) + 22
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            WorkspaceSidebarScopeSegmentedControl(
                scopes: quickScopes,
                selectedScopeId: browsedProjectId == nil ? selectedScopeId : nil,
                onSelect: onSelectScope
            )
            .frame(width: scopeControlWidth, height: workspaceSidebarDropdownHeight)
            if !browsableProjects.isEmpty { projectSelector }
            Spacer(minLength: 0)
        }
        .frame(width: sectionWidth, height: workspaceSidebarDropdownHeight, alignment: .leading)
        .opacity(expansionProgress)
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarWillCollapseNotification)) { _ in
            isProjectMenuOpen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarDismissProjectMenusNotification)) { _ in
            isProjectMenuOpen = false
        }
    }

    @ViewBuilder
    private var projectSelector: some View {
        if !measuring, let selectedProject, renamingProjectId == selectedProject.id {
            WorkspaceSidebarProjectRenameField(
                project: selectedProject, text: $renamingProjectText,
                onCommit: onCommitRenameProject, onCancel: onCancelRenameProject
            )
            .frame(width: selectorWidth, height: workspaceSidebarDropdownHeight)
        } else {
            WorkspaceSidebarNativeProjectMenu(
                projects: browsableProjects,
                selectedProjectId: browsedProjectId,
                title: selectedProject?.displayName ?? "Other Projects",
                isMenuOpen: $isProjectMenuOpen,
                onSelect: { projectId in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        onSelectProject(projectId == browsedProjectId ? nil : projectId)
                    }
                },
                onRename: onRenameProject,
                onSetColor: onSetProjectColor,
                onDelete: onDeleteProject
            )
            .frame(width: selectorWidth, height: workspaceSidebarDropdownHeight)
            .help("Browse another project")
        }
    }

    private var selectorWidth: CGFloat {
        min(projectPopupWidth, max(sectionWidth - scopeControlWidth - 3, 36))
    }
}
