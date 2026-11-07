import Foundation

struct FrozenWorld: Codable, Equatable, Sendable {
    let workspaces: [FrozenWorkspace]
    let monitors: [FrozenMonitor]
    let windowIds: Set<UInt32>
}

extension FrozenWorld {
    /// One workspace or monitor that cannot be read, as after running an older build, is left out
    /// instead of costing every other workspace its layout.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaces = try container.decode(LossyDecodableArray<FrozenWorkspace>.self, forKey: .workspaces).elements
        monitors = try container.decode(LossyDecodableArray<FrozenMonitor>.self, forKey: .monitors).elements
        windowIds = try container.decode(Set<UInt32>.self, forKey: .windowIds)
    }
}

/// An array decoded one element at a time, leaving out the elements that cannot be read.
struct LossyDecodableArray<Element: Decodable>: Decodable {
    let elements: [Element]
    /// How many elements were left out.
    let skipped: Int

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var skipped = 0
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode does not move past the element; reading it as nothing does.
                _ = try container.decode(SkippedValue.self)
                skipped += 1
            }
        }
        if skipped > 0 { NSLog("WinMuxX: left out %d unreadable saved %@ entries", skipped, String(describing: Element.self)) }
        self.elements = elements
        self.skipped = skipped
    }

    private struct SkippedValue: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

@MainActor
func snapshotCurrentFrozenWorld() -> FrozenWorld {
    let workspaces = restorableWorkspaces(Workspace.all)
    return FrozenWorld(
        workspaces: workspaces.map { FrozenWorkspace($0) },
        monitors: monitors.map(FrozenMonitor.init),
        windowIds: workspaces.flatMap { collectAllWindowIds(workspace: $0) }.toSet(),
    )
}

@MainActor
func restorableWorkspaces(_ workspaces: [Workspace]) -> [Workspace] {
    workspaces.filter { !collectAllWindowIds(workspace: $0).isEmpty || $0.isConfiguredPersistent }
}

@MainActor
func collectAllWindowIds(workspace: Workspace) -> [UInt32] {
    workspace.floatingWindows.map { $0.windowId } +
        workspaceOwnedMinimizedWindows(workspace).map { $0.windowId } +
        (workspace.existingMacOsNativeFullscreenWindowsContainer?.children.filterIsInstance(of: Window.self).map { $0.windowId } ?? []) +
        (workspace.existingMacOsNativeHiddenAppsWindowsContainer?.children.filterIsInstance(of: Window.self).map { $0.windowId } ?? []) +
        collectAllWindowIdsRecursive(workspace.rootTilingContainer)
}

func collectAllWindowIdsRecursive(_ node: TreeNode) -> [UInt32] {
    switch node.nodeCases {
        case .macosFullscreenWindowsContainer,
             .macosHiddenAppsWindowsContainer,
             .macosMinimizedWindowsContainer,
             .macosPopupWindowsContainer,
             .workspace: []
        case .tilingContainer(let c):
            c.children.reduce(into: [UInt32]()) { partialResult, elem in
                partialResult += collectAllWindowIdsRecursive(elem)
            }
        case .window(let w): [w.windowId]
    }
}
