import Common
import NativeSpaces

// With native Spaces the sidebar lists macOS desktops instead of virtual workspaces.
// Rows reuse the virtual view models; selection routes through native navigation,
// dragging a window onto a desktop moves it there, and renaming saves a
// `workspace-labels` entry keyed by desktop number. Virtual-only edits (create,
// delete, tab-group drags, projects) are unavailable.

/// Desktops in macOS Control-N order, with the windows each native layout retains.
/// Desktops not yet visited show no windows until their layout is first observed.
@MainActor
func buildNativeWorkspaceSidebarWorkspaceViewModels(
    currentFocus: LiveFocus,
    workspaceLabels: [String: String],
    availableMonitors: [Monitor],
) async -> [WorkspaceSidebarWorkspaceViewModel] {
    let layouts = runtime.workspaceBackend.nativeLayouts
    guard let displays = nativeObservedDisplays() else { return [] }
    var result: [WorkspaceSidebarWorkspaceViewModel] = []
    var number = 0
    for display in displays {
        let monitor = display.identifier == "Main" ? mainMonitor : availableMonitors.first { $0.displayUUID == display.identifier }
        for space in display.spaces where space.isDesktop {
            number += 1
            guard let monitor, let uuid = space.uuid, let workspace = layouts.retainedByUUID[uuid] else { continue }
            let label = nativeDesktopLabel(number, labels: workspaceLabels)
            let isActive = space.id == display.activeSpaceID
            result.append(WorkspaceSidebarWorkspaceViewModel(
                name: workspace.name,
                projectId: workspace.projectId,
                displayName: nativeDesktopDisplayName(number, labels: workspaceLabels),
                sidebarLabel: label,
                isGeneratedName: true,
                monitorScopeId: workspaceSidebarMonitorScopeId(for: monitor),
                monitorName: availableMonitors.count > 1 ? monitor.name : nil,
                isFocused: isActive && currentFocus.workspace === workspace,
                isVisible: isActive,
                items: await buildWorkspaceSidebarItems(for: workspace, currentFocus: currentFocus),
            ))
        }
    }
    return result
}

/// Handles a sidebar action in native mode. Actions that only make sense for
/// virtual workspaces explain why they are unavailable instead of acting.
@MainActor
func handleNativeWorkspaceSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel) {
    switch action {
        case .selectWorkspace(let name), .overrideWorkspaceInUse(let name):
            guard let number = nativeDesktopNumber(forSidebarWorkspace: name) else { return }
            runNativeSidebarCommands(["workspace \(number)"])
        case .selectWindow(let windowId):
            runNativeSidebarCommands(nativeFocusWindowCommands(windowId))
        case .selectMonitorScope(let scopeId):
            selectWorkspaceSidebarMonitorScope(scopeId, viewModel: viewModel)
        case .clearDropPreview:
            clearWorkspaceSidebarDropPreview()
        case .previewWindowDrop, .previewTabGroupDrop:
            break
        case .moveWindow(let windowId, let name):
            guard let number = nativeDesktopNumber(forSidebarWorkspace: name) else { return }
            runNativeSidebarCommands(["move-node-to-workspace --window-id \(windowId) \(number)"])
        case .renameWorkspace(let name, let displayName):
            guard let number = nativeDesktopNumber(forSidebarWorkspace: name) else { return }
            renameNativeDesktop(number, to: displayName)
        case .createWorkspace, .deleteWorkspace, .moveTabGroup,
             .moveWindowToNewWorkspace, .moveTabGroupToNewWorkspace,
             .selectProject, .createProject, .renameProject, .setProjectColor, .deleteProject:
            showWorkspaceSidebarError("macOS owns native Spaces: add, remove and rearrange desktops in Mission Control. Projects are available with virtual workspaces.")
    }
}

/// An empty name returns the desktop to "Desktop N". Labels follow the desktop's
/// position, as Control-N does.
@MainActor
func renameNativeDesktop(_ number: Int, to displayName: String) {
    let label = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    runWorkspaceSidebarSession {
        if !isUnitTest { try persistWorkspaceSidebarLabel(workspaceName: String(number), label: label.isEmpty ? nil : label) }
        config.workspaceSidebar.workspaceLabels[String(number)] = label.isEmpty ? nil : label
        updateTrayText()
        await updateWorkspaceSidebarModel()
    }
}

/// Commands run one after another; a Space switch must land before focusing.
@MainActor
private func runNativeSidebarCommands(_ commands: [String]) {
    WorkspaceSidebarPanel.suppressEdgeTrapForWorkspaceActivation()
    runWorkspaceSidebarSession {
        if let error = try await runNativeCommands(commands) { return showWorkspaceSidebarError(error) }
        await updateWorkspaceSidebarModel()
    }
}
