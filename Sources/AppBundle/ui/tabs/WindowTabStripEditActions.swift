import Common
@MainActor
func removeWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
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
        try await runLightSession(.menuBarButton, token) {
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
/// one of those groups.
@MainActor
func reorderWorkspaceTab(_ window: Window, stripId: ObjectIdentifier, toIndex targetIndex: Int) -> Bool {
    guard let workspace = window.nodeWorkspace, workspace.arrangement == .tabbed,
          let group = workspace.tabbedGroup(containing: window.windowId), ObjectIdentifier(group) == stripId else { return false }
    return workspace.reorderTabbedTab(window.windowId, toIndex: targetIndex)
}

/// Moves a tab of a Tabbed workspace into a new tab group on `side` of its own.
@MainActor
func moveTabToNewGroupFromTabStrip(_ windowId: UInt32, side: CardinalDirection) {
    editTabbedGroupsFromTabStrip(windowId) { workspace, group in workspace.moveTabbedTabToNewGroup(windowId, beside: group, on: side) }
}

/// Moves a tab of a Tabbed workspace into the tab group on `direction`'s side of its own.
@MainActor
func moveTabToNeighborGroupFromTabStrip(_ windowId: UInt32, _ direction: CardinalDirection) {
    editTabbedGroupsFromTabStrip(windowId) { workspace, group in
        workspace.tabbedGroup(beside: group, direction).map { workspace.moveTabbedTab(windowId, into: $0) } ?? false
    }
}

/// Moves every tab of the tab's group into the group on `direction`'s side.
@MainActor
func mergeTabGroupFromTabStrip(_ windowId: UInt32, _ direction: CardinalDirection) {
    editTabbedGroupsFromTabStrip(windowId) { workspace, group in
        workspace.tabbedGroup(beside: group, direction).map { workspace.mergeTabbedGroup(group, into: $0) } ?? false
    }
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
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId), let workspace = window.nodeWorkspace, workspace.arrangement == .tabbed,
                  let group = workspace.tabbedGroup(containing: windowId), edit(workspace, group) else { return }
            _ = window.focusWindow()
        }
    }
}

/// The sides of a tab's group where another group lies, for the bar's menus.
@MainActor
func tabbedGroupNeighborSides(of windowId: UInt32) -> [CardinalDirection] {
    guard let workspace = Window.get(byId: windowId)?.nodeWorkspace, workspace.arrangement == .tabbed,
          let group = workspace.tabbedGroup(containing: windowId) else { return [] }
    return [.left, .right, .up, .down].filter { workspace.tabbedGroup(beside: group, $0) != nil }
}

extension CardinalDirection {
    /// Names the group on that side in menu items: "Merge With Group on the Left".
    var tabbedGroupSideTitle: String {
        switch self {
            case .left: "on the Left"
            case .right: "on the Right"
            case .up: "Above"
            case .down: "Below"
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
