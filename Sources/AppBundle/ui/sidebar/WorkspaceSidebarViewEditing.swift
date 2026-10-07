import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarView {
    func beginProjectRename(_ project: WorkspaceSidebarProjectViewModel) {
        debugWorkspaceSidebarRenameLog("beginProjectRename project=\(project.id.rawValue) displayName=\(project.displayName) active=\(snapshot.activeProjectId.rawValue) visibleWidth=\(snapshot.visibleWidth)")
        finishSidebarSearch(clearText: false)
        if project.id != snapshot.activeProjectId {
            browseMode = .split(otherProjectId: project.id)
        }
        renamingProjectId = project.id
        renamingProjectText = project.displayName
        isProjectMenuOpen = false
        currentPanel()?.prepareForInlineTextEditing()
    }

    func finishProjectRename(cancelled: Bool = false) {
        guard let projectId = renamingProjectId else { return }
        let displayName = renamingProjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        debugWorkspaceSidebarRenameLog("finishProjectRename project=\(projectId.rawValue) cancelled=\(cancelled) raw=\(renamingProjectText) trimmed=\(displayName)")
        renamingProjectId = nil
        renamingProjectText = ""
        currentPanel()?.endInlineTextEditing()
        guard !cancelled, !displayName.isEmpty else { return }
        actions.send(.renameProject(projectId, displayName: displayName))
    }

    func beginWorkspaceRename(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
        debugWorkspaceSidebarRenameLog("beginWorkspaceRename workspace=\(workspace.name) displayName=\(workspace.displayName) targetScope=\(snapshot.targetMonitorScopeId) activeProject=\(snapshot.activeProjectId.rawValue) visibleWidth=\(snapshot.visibleWidth)")
        finishSidebarSearch(clearText: false)
        finishProjectRename(cancelled: true)
        renamingWorkspaceName = workspace.name
        renamingWorkspaceText = workspace.displayName
        currentPanel()?.prepareForInlineTextEditing()
    }

    func finishWorkspaceRename(cancelled: Bool = false) {
        guard let workspaceName = renamingWorkspaceName else { return }
        let displayName = renamingWorkspaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        debugWorkspaceSidebarRenameLog("finishWorkspaceRename workspace=\(workspaceName) cancelled=\(cancelled) raw=\(renamingWorkspaceText) trimmed=\(displayName) targetScope=\(snapshot.targetMonitorScopeId)")
        renamingWorkspaceName = nil
        renamingWorkspaceText = ""
        currentPanel()?.endInlineTextEditing()
        guard !cancelled, !displayName.isEmpty else { return }
        actions.send(.renameWorkspace(workspaceName, displayName: displayName))
    }

    func currentPanel() -> WorkspaceSidebarPanel? {
        WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId)
    }

    func beginSidebarSearchIfNeeded(panel: WorkspaceSidebarPanel? = nil) {
        guard renamingProjectId == nil, renamingWorkspaceName == nil, !isSearchEditing else { return }
        guard snapshot.visibleWidth > snapshot.configuration.collapsedWidth + 0.5 || isSidebarExpanding else { return }
        let editingPanel = panel ?? currentPanel() ?? WorkspaceSidebarPanel.shared
        adoptCommandSidebarSearchIfNeeded(panel: editingPanel)
    }

    func adoptCommandSidebarSearchIfNeeded(panel editingPanel: WorkspaceSidebarPanel) {
        guard renamingProjectId == nil, renamingWorkspaceName == nil else { return }
        let startsEditing = !isSearchEditing || searchEditingPanel !== editingPanel
        if startsEditing {
            isSearchEditing = true
            searchEditingPanel = editingPanel
            selectFirstSearchTarget()
        }
        let locksExpansion = editingPanel.commandExpansionLocksCollapse || editingPanel.shouldLockNextSidebarSearchExpansion
        searchUsesNativeEditor = searchUsesNativeEditor || locksExpansion
        editingPanel.shouldLockNextSidebarSearchExpansion = false
        if startsEditing {
            editingPanel.beginInlineTextEditing(
                locksExpansion: locksExpansion,
                cancelsOnPointerExit: false,
                activatesWindow: searchUsesNativeEditor,
                onCancel: {
                    finishSidebarSearch(clearText: true)
                },
                onKeyDown: { key in
                    handleSidebarSearchKey(key)
                },
            )
        }
        let bufferedKeys = editingPanel.bufferedCommandSidebarSearchKeys
        editingPanel.bufferedCommandSidebarSearchKeys = []
        for key in bufferedKeys {
            handleSidebarSearchKey(key)
        }
    }

    func finishSidebarSearch(clearText: Bool) {
        let panel = searchEditingPanel
        if isSearchEditing {
            isSearchEditing = false
            (panel ?? currentPanel() ?? WorkspaceSidebarPanel.shared).endInlineTextEditing()
            searchEditingPanel = nil
        }
        if clearText {
            searchText = ""
        }
        selectedSearchTarget = nil
        searchUsesNativeEditor = false
    }

    func handleSidebarSearchKey(_ key: WorkspaceSidebarInlineTextKey) {
        // Only buffered keys and the first hover-search keystroke use this path.
        // Once the native editor is focused, AppKit handles text editing.
        if case .text = key { searchUsesNativeEditor = true }
        switch key {
            case .text(let inserted):
                searchText += inserted
                selectFirstSearchTarget()
            case .deleteBackward:
                if !searchText.isEmpty {
                    searchText.removeLast()
                }
                selectFirstSearchTarget()
            case .deleteWordBackward:
                searchText.deleteLastWord()
                selectFirstSearchTarget()
            case .deleteToBeginningOfLine:
                searchText = ""
                selectedSearchTarget = nil
            case .deleteForward:
                break
            case .commit:
                activateSelectedSearchTarget()
            case .cancel:
                let panel = searchEditingPanel ?? WorkspaceSidebarPanel.shared
                finishSidebarSearch(clearText: true)
                closeWorkspaceSidebarFromCommand(panel)
            case .moveUp:
                moveSearchSelection(delta: -1)
            case .moveDown:
                moveSearchSelection(delta: 1)
            case .ignored:
                break
        }
    }

    func sidebarSearchEditorReady(on panel: WorkspaceSidebarPanel) {
        searchUsesNativeEditor = true
        if !isSearchEditing {
            adoptCommandSidebarSearchIfNeeded(panel: panel)
        }
        searchEditingPanel = panel
        panel.removeInlineTextEditingKeyEventTap()
    }

    func selectFirstSearchTarget() {
        selectedSearchTarget = searchText.isEmpty ? nil : currentSearchSelections().first
    }

    func moveSearchSelection(delta: Int) {
        let selections = currentSearchSelections()
        guard !selections.isEmpty else {
            selectedSearchTarget = nil
            return
        }
        guard let selectedSearchTarget,
              let index = selections.firstIndex(of: selectedSearchTarget)
        else {
            self.selectedSearchTarget = selections.first
            return
        }
        let nextIndex = max(0, min(selections.count - 1, index + delta))
        self.selectedSearchTarget = selections[nextIndex]
    }

    func activateSelectedSearchTarget() {
        guard let selectedSearchTarget else { return }
        let panel = searchEditingPanel ?? WorkspaceSidebarPanel.shared
        switch selectedSearchTarget {
            case .workspace(let workspaceName):
                actions.send(.selectWorkspace(workspaceName))
            case .window(let windowId):
                actions.send(.selectWindow(windowId))
        }
        finishSidebarSearch(clearText: true)
        closeWorkspaceSidebarFromCommand(panel)
    }

    func currentSearchSelections() -> [WorkspaceSidebarSearchSelection] {
        let workspaces = currentFilteredProjectWorkspaces()
        return workspaceSidebarSearchSelections(workspaces: workspaces)
    }

    func currentFilteredProjectWorkspaces() -> [WorkspaceSidebarWorkspaceViewModel] {
        let visibleWorkspacesByProject = workspaceSidebarVisibleWorkspacesByProject(
            workspaces: snapshot.workspaces,
            selectedScopeId: snapshot.selectedMonitorScopeId,
            focusedMonitorScopeId: snapshot.focusedMonitorScopeId,
            browsedProjectId: browsedProjectId,
        )
        let filteredWorkspacesByProject = workspaceSidebarFilteredWorkspacesByProject(
            visibleWorkspacesByProject,
            projects: snapshot.projects,
            query: searchText,
        )
        let projectId: WorkspaceProjectId
        if let index = projectPagerDisplayIndex, snapshot.projects.indices.contains(index) {
            projectId = snapshot.projects[index].id
        } else {
            projectId = snapshot.activeProjectId
        }
        return filteredWorkspacesByProject[projectId] ?? []
    }
}
