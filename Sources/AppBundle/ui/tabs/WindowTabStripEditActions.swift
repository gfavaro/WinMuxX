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

/// Moves a Tabbed workspace's tab by swapping windows between their places in the tree one step
/// at a time, so the hidden splits keep their shape and only which window sits where changes.
/// Returns false when the strip is not that workspace's bar.
@MainActor
func reorderWorkspaceTab(_ window: Window, stripId: ObjectIdentifier, toIndex targetIndex: Int) -> Bool {
    guard let workspace = window.nodeWorkspace, workspace.arrangement == .tabbed, ObjectIdentifier(workspace) == stripId else { return false }
    var tabs = workspace.rootTilingContainer.allLeafWindowsRecursive
    guard var index = tabs.firstIndex(where: { $0 === window }) else { return false }
    let target = max(0, min(targetIndex, tabs.count - 1))
    while index != target {
        let next = index + (target > index ? 1 : -1)
        swapNodes(tabs[index], tabs[next])
        tabs.swapAt(index, next)
        index = next
    }
    window.markAsMostRecentChild()
    return true
}

/// Strip index a keyboard or VoiceOver move lands on, or nil at either end of the strip.
func windowTabStripMoveTargetIndex(_ windowId: UInt32, by offset: Int, in tabs: [WindowTabItemViewModel]) -> Int? {
    guard let index = tabs.firstIndex(where: { $0.windowId == windowId }),
          tabs.indices.contains(index + offset)
    else { return nil }
    return index + offset
}
