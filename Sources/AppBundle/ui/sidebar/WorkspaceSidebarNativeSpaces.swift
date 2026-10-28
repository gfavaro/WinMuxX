import AppKit
import Common
import NativeSpaces

// With native Spaces the sidebar lists macOS desktops instead of virtual workspaces.
// Rows reuse the virtual view models; selection routes through native navigation,
// dragging a window onto a desktop moves it there, and renaming saves a
// `workspace-labels` entry keyed by desktop number. Virtual-only edits (create,
// delete, tab-group drags, projects) are unavailable.

/// Desktops in macOS Control-N order, with the windows each native layout retains,
/// then windows WindowServer reports on desktops not showing, which are adopted once
/// their desktop is visited.
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
                items: await buildWorkspaceSidebarItems(for: workspace, currentFocus: currentFocus) +
                    nativeListedSidebarItems(space.id, workspaceName: workspace.name),
            ))
        }
    }
    return result
}

@MainActor
private func nativeListedSidebarItems(_ spaceID: String, workspaceName: String) -> [WorkspaceSidebarItemViewModel] {
    (NativeUnvisitedWindows.shared.bySpaceID[spaceID] ?? []).map { listed in
        let app = NSRunningApplication(processIdentifier: listed.pid)
        return .init(kind: .window(WorkspaceSidebarWindowViewModel(
            windowId: listed.windowId, workspaceName: workspaceName,
            appName: app?.localizedName ?? app?.bundleIdentifier ?? "Unknown",
            appBundleId: app?.bundleIdentifier, appBundlePath: app?.bundleURL?.path,
            title: listed.title, isFocused: false)))
    }
}

/// Handles a sidebar action in native mode. Actions that only make sense for
/// virtual workspaces explain why they are unavailable instead of acting.
@MainActor
func handleNativeWorkspaceSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel,
                                       targetMonitorScopeId: String? = nil) {
    switch action {
        case .overrideWorkspaceInUse(let name):
            // macOS keeps the desktop on its display; its windows and layout come here.
            guard let (args, env) = nativeBringHere(name, targetMonitorScopeId: targetMonitorScopeId) else { return }
            WorkspaceSidebarPanel.suppressEdgeTrapForWorkspaceActivation()
            runWorkspaceSidebarSession {
                let io = CmdIo(stdin: .emptyStdin)
                if !(await runtime.workspaceBackend.nativeWindowMoves.run(args, env: env, io: io)) {
                    showWorkspaceSidebarError(io.stderr.last ?? "Bring Here failed")
                }
                await updateWorkspaceSidebarModel()
            }
        case .selectWorkspace(let name):
            guard let number = nativeDesktopNumber(forSidebarWorkspace: name) else { return }
            optimisticallyMarkNativeDesktopShown(name)
            runNativeSidebarCommands(["workspace \(number)"])
        case .selectWindow(let windowId):
            WorkspaceSidebarPanel.suppressEdgeTrapForWorkspaceActivation()
            runWorkspaceSidebarSession {
                if let error = try await focusNativeWindow(windowId) { return showWorkspaceSidebarError(error) }
                await updateWorkspaceSidebarModel()
            }
        case .selectMonitorScope(let scopeId):
            selectWorkspaceSidebarMonitorScope(scopeId, viewModel: viewModel)
        case .clearDropPreview:
            clearWorkspaceSidebarDropPreview()
        case .previewWindowDrop, .previewTabGroupDrop:
            break
        case .moveWindow(let windowId, let name):
            guard let number = nativeDesktopNumber(forSidebarWorkspace: name) else { return }
            if Window.get(byId: windowId) == nil, NativeUnvisitedWindows.shared.spaceID(of: windowId) != nil {
                // Listed only: no tree holds it yet, so it moves by ID.
                runWorkspaceSidebarSession {
                    let io = CmdIo(stdin: .emptyStdin)
                    if !(await runtime.workspaceBackend.nativeWindowMoves.moveListed(windowId, toDesktop: number, io: io)) {
                        showWorkspaceSidebarError(io.stderr.last ?? "Move failed")
                    }
                    await updateWorkspaceSidebarModel()
                }
                return
            }
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

/// "Bring Here": move a desktop's windows to the desktop the sidebar's display shows.
/// Native desktop names are reserved, so the desktop travels in the command env.
@MainActor
func nativeBringHere(_ name: String, targetMonitorScopeId: String?) -> (MoveWorkspaceToMonitorCmdArgs, CmdEnv)? {
    guard let source = Workspace.existing(byName: name) else { return nil }
    let monitors = sortedMonitors
    let scope = targetMonitorScopeId.flatMap { id in monitors.firstIndex { workspaceSidebarMonitorScopeId(for: $0) == id } }
    guard let index = scope ?? monitors.firstIndex(where: { $0.rect.contains(mouseLocation) }),
          nativeActiveDesktop(on: monitors[index]) !== source,
          case .cmd(let command) = parseCommand("move-workspace-to-monitor \(index + 1)"),
          let move = command as? MoveWorkspaceToMonitorCommand else { return nil }
    return (move.args, .defaultEnv.copy(\.workspaceName, source.name))
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
        // The model is rebuilt either way, so a failed switch undoes its optimistic highlight.
        if let error = try await runNativeCommands(commands) { showWorkspaceSidebarError(error) }
        await updateWorkspaceSidebarModel()
    }
}

/// Highlights the clicked desktop as shown on its display on the click's frame, as virtual
/// workspaces do; the swipe can take a few hundred ms to land. Desktops never change display.
@MainActor
private func optimisticallyMarkNativeDesktopShown(_ name: String) {
    let workspaces = TrayMenuModel.shared.workspaceSidebarWorkspaces
    guard let clicked = workspaces.first(where: { $0.name == name }), !clicked.isVisible else { return }
    let display = clicked.monitorScopeId
    let focusMoves = workspaces.contains { $0.monitorScopeId == display && $0.isFocused }
    TrayMenuModel.shared.workspaceSidebarWorkspaces = workspaces.map { w in
        guard w.monitorScopeId == display else { return w }
        let shown = w.name == name
        return WorkspaceSidebarWorkspaceViewModel(
            name: w.name,
            projectId: w.projectId,
            displayName: w.displayName,
            sidebarLabel: w.sidebarLabel,
            isGeneratedName: w.isGeneratedName,
            monitorScopeId: w.monitorScopeId,
            monitorName: w.monitorName,
            isFocused: shown && focusMoves,
            isVisible: shown,
            items: w.items,
        )
    }
    WorkspaceSidebarPanel.syncVisiblePanelModelsFromShared()
}
