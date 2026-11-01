import AppKit

/// Native tab groups keep inactive tabs at the active tab's frame instead of parking
/// them in a corner, so every window stays visible in Mission Control and reachable if
/// WinMuxX quits; Accordion overlaps its windows. The active window must therefore be
/// frontmost within its group. After a
/// native layout, an active tab that a sibling covers is raised with AX, which does not
/// activate its app; a raise that would move keyboard focus to another window of the
/// frontmost app is skipped until focus agrees. Approach adapted from Dinky (MIT).
@MainActor
func raiseCoveredNativeTabs(in workspace: Workspace, frontToBack: [UInt32]) async {
    let position = Dictionary(frontToBack.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
    for active in nativeTabsToRaise(in: workspace, position: position) {
        if active.macApp.pid == frontmostPid, focus.windowOrNil?.windowId != active.windowId { continue }
        try? await active.macApp.raiseWithoutActivating(active.windowId)
    }
}

/// Active tabs some sibling in their group is in front of; `position` is front-to-back.
@MainActor
func nativeTabsToRaise(in workspace: Workspace, position: [UInt32: Int]) -> [MacWindow] {
    workspace.rootTilingContainer.allStackingContainersRecursive.compactMap { group in
        guard let active = group.tabActiveWindow as? MacWindow, let activeIndex = position[active.windowId] else { return nil }
        let covered = group.allLeafWindowsRecursive.contains { $0 !== active && (position[$0.windowId] ?? .max) < activeIndex }
        return covered ? active : nil
    }
}

extension TilingContainer {
    /// Tabbed and Accordion groups, whose windows overlap natively.
    @MainActor var allStackingContainersRecursive: [TilingContainer] {
        let nested = children.flatMap { ($0 as? TilingContainer)?.allStackingContainersRecursive ?? [] }
        return ([.tabGroup, .stacked].contains(layout) && children.count > 1 ? [self] : []) + nested
    }
}

/// On-screen window ids, front to back.
func onScreenWindowOrder() -> [UInt32] {
    (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
        .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
}

extension Window {
    /// A tab other than its group's active one; native mode stacks these behind it.
    @MainActor var isInactiveWindowTab: Bool {
        guard let group = nearestWindowTabGroup, group.usesWindowTabBehavior else { return false }
        return group.tabActiveWindow !== self
    }
}
