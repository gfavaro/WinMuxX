import Common
@MainActor
func removeWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        await runUnattendedLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId) else {
                _ = try await selectWorkspaceFromUi(fallbackWorkspace)
                return
            }
            _ = removeWindowFromTabStack(window)
            window.nativeFocus()
        }
    }
}

@MainActor
func reorderTabInStrip(_ windowId: UInt32, stripId: ObjectIdentifier, toIndex targetIndex: Int) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        await runUnattendedLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId),
                  reorderTabGroupChild(showing: window, stripId: stripId, toIndex: targetIndex)
                    || reorderWorkspaceTab(window, stripId: stripId, toIndex: targetIndex)
            else { return }
            _ = window.focusWindow()
        }
    }
}

/// A tab can stand for a nested container, so this moves the strip container's direct child
/// that holds `window`, not the window inside its own parent. Returns false when `window` is not
/// under the strip's tab group.
@MainActor
func reorderTabGroupChild(showing window: Window, stripId: ObjectIdentifier, toIndex targetIndex: Int) -> Bool {
    var child: TreeNode = window
    while let parent = child.parent {
        if let group = parent as? TilingContainer, group.layout == .tabGroup, ObjectIdentifier(group) == stripId {
            guard let currentIndex = child.ownIndex else { return false }
            let clampedTarget = max(0, min(targetIndex, group.children.count - 1))
            if clampedTarget != currentIndex {
                let binding = child.unbindFromParent()
                child.bind(to: group, adaptiveWeight: binding.adaptiveWeight, index: clampedTarget)
            }
            window.markAsMostRecentChild()
            return true
        }
        child = parent
    }
    return false
}

/// Moves a tab along a Tabbed workspace's tab group bar. Returns false when the strip is not
/// one of those groups. A bar showing folded groups keeps each tab in its own group: it moves
/// as far toward the drop as its group's tabs reach.
@MainActor
func reorderWorkspaceTab(_ window: Window, stripId: ObjectIdentifier, toIndex targetIndex: Int) -> Bool {
    guard let workspace = window.nodeWorkspace, workspace.arrangement == .tabbed,
          let group = workspace.tabbedGroup(containing: window.windowId), ObjectIdentifier(group.barGroup) == stripId else { return false }
    let bar = group.barGroup.barWindowIds, own = group.shownWindowIds
    guard let anchor = bar.getOrNil(atIndex: max(0, min(targetIndex, bar.count - 1))) else { return false }
    let index = own.firstIndex(of: anchor)
        ?? ((bar.firstIndex(of: anchor) ?? 0) < (bar.firstIndex(of: own.first ?? anchor) ?? 0) ? 0 : own.count - 1)
    return workspace.reorderTabbedTab(window.windowId, toIndex: index)
}

/// Moves a tab of a Tabbed workspace into a new tab group on `side` of its own.
@MainActor
func moveTabToNewGroupFromTabStrip(_ windowId: UInt32, side: CardinalDirection) {
    editTabbedGroupsFromTabStrip(windowId) { workspace, group in workspace.moveTabbedTabToNewGroup(windowId, beside: group, on: side) }
}

/// Gathers every tab group of the tab's workspace into the tab's own.
@MainActor
func mergeAllTabGroupsFromTabStrip(_ windowId: UInt32) {
    editTabbedGroupsFromTabStrip(windowId) { workspace, group in workspace.mergeAllTabbedGroups(into: group) }
}

@MainActor
private func editTabbedGroupsFromTabStrip(_ windowId: UInt32, _ edit: @escaping @MainActor (Workspace, TabbedGroup) -> Bool) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        await runUnattendedLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId), let workspace = window.nodeWorkspace, workspace.arrangement == .tabbed,
                  let group = workspace.tabbedGroup(containing: windowId), edit(workspace, group) else { return }
            _ = window.focusWindow()
        }
    }
}


/// Strip index a keyboard or VoiceOver move lands on, or nil at either end of the strip.
func windowTabStripMoveTargetIndex(_ windowId: UInt32, by offset: Int, in tabs: [WindowTabItemViewModel]) -> Int? {
    guard let index = tabs.firstIndex(where: { $0.windowId == windowId }),
          tabs.indices.contains(index + offset)
    else { return nil }
    return index + offset
}
