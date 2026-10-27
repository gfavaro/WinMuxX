import Common
import NativeSpaces

// With native Spaces the sidebar lists macOS desktops instead of virtual workspaces.
// Rows reuse the virtual view models; selection routes through native navigation,
// dragging a window onto a desktop moves it there, and virtual-only edits (create,
// rename, delete, tab-group drags, projects) are unavailable.

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

/// A `workspace-labels` entry keyed by desktop number names that desktop.
func nativeDesktopLabel(_ number: Int, labels: [String: String]) -> String {
    labels[String(number)]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

@MainActor
func nativeDesktopDisplayName(_ number: Int, labels: [String: String]? = nil) -> String {
    let label = nativeDesktopLabel(number, labels: labels ?? config.workspaceSidebar.workspaceLabels)
    return label.isEmpty ? "Desktop \(number)" : label
}

/// The last observation stays listed during a read, so rows don't flicker away.
@MainActor
func nativeObservedDisplays() -> [NativeSpaceDisplay]? {
    let backend = runtime.workspaceBackend
    return (backend.observation?.inventory.lastSnapshot ?? backend.nativeLayouts.snapshot)?.displays
}

/// The Control-N number of the desktop a native sidebar row stands for.
@MainActor
func nativeDesktopNumber(forSidebarWorkspace name: String) -> Int? {
    let layouts = runtime.workspaceBackend.nativeLayouts
    guard let displays = nativeObservedDisplays() else { return nil }
    var number = 0
    for display in displays {
        for space in display.spaces where space.isDesktop {
            number += 1
            if let uuid = space.uuid, layouts.retainedByUUID[uuid]?.name == name { return number }
        }
    }
    return nil
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
            var commands: [String] = []
            if let name = workspaceSidebarFallbackWorkspaceName(for: windowId),
               let row = viewModel.workspaceSidebarWorkspaces.first(where: { $0.name == name }), !row.isVisible,
               let number = nativeDesktopNumber(forSidebarWorkspace: name) {
                commands.append("workspace \(number)")
            }
            if runtime.workspaceBackend.nativeTilingEnabled { commands.append("focus --window-id \(windowId)") }
            runNativeSidebarCommands(commands)
        case .selectMonitorScope(let scopeId):
            selectWorkspaceSidebarMonitorScope(scopeId, viewModel: viewModel)
        case .clearDropPreview:
            clearWorkspaceSidebarDropPreview()
        case .previewWindowDrop, .previewTabGroupDrop:
            break
        case .moveWindow(let windowId, let name):
            guard let number = nativeDesktopNumber(forSidebarWorkspace: name) else { return }
            runNativeSidebarCommands(["move-node-to-workspace --window-id \(windowId) \(number)"])
        case .createWorkspace, .renameWorkspace, .deleteWorkspace, .moveTabGroup,
             .moveWindowToNewWorkspace, .moveTabGroupToNewWorkspace,
             .selectProject, .createProject, .renameProject, .setProjectColor, .deleteProject:
            showWorkspaceSidebarError("macOS owns native Spaces: add, remove and rearrange desktops in Mission Control. Projects are available with virtual workspaces.")
    }
}

/// Commands run one after another; a Space switch must land before focusing.
@MainActor
private func runNativeSidebarCommands(_ commands: [String]) {
    WorkspaceSidebarPanel.suppressEdgeTrapForWorkspaceActivation()
    runWorkspaceSidebarSession {
        for text in commands {
            guard case .cmd(let command) = parseCommand(text) else { continue }
            let io = CmdIo(stdin: .emptyStdin)
            guard try await [command].runCmdSeq(.defaultEnv, io) else {
                if let error = io.stderr.last { showWorkspaceSidebarError(error) }
                return
            }
        }
        await updateWorkspaceSidebarModel()
    }
}
