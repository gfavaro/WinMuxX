import AppKit
import Common
import PrivateApi

/// One tab group of a Tabbed workspace: its tabs in bar order and the window it shows.
/// Groups refer to windows by ID and leave the window tree untouched, so Dwindle and Master
/// return to exactly the layout they had.
@MainActor
final class TabbedGroup {
    var windowIds: [UInt32]
    var activeWindowId: UInt32?
    /// The group's area from the last layout: tab bar and window together. Nil while hidden or folded.
    var lastFrame: Rect?
    /// Groups the display had no room for at the last layout, shown for now as tabs in this group's
    /// bar and area. The groups themselves stay as they are, and come back when there is room.
    var foldedGroups: [TabbedGroup] = []
    /// The group whose bar shows this one's tabs while it is folded.
    weak var foldedInto: TabbedGroup?
    /// Which of this group and those folded into it was used last, and so is shown in its area.
    weak var displayedMember: TabbedGroup?
    /// How far its bar has scrolled its tabs, as the bar reports: zero, or negative once tabs have
    /// scrolled out to the left. Drops onto the bar land by where its tabs are now.
    var barScrollOffset: CGFloat = 0

    init(windowIds: [UInt32], activeWindowId: UInt32? = nil) {
        self.windowIds = windowIds
        self.activeWindowId = activeWindowId ?? windowIds.first
    }

    /// The window shown: the chosen tab, or while its window is briefly missing the first shown
    /// one, without changing the choice, so the chosen tab returns with its window.
    var activeWindow: Window? {
        let shown = shownWindowIds
        let id = activeWindowId.flatMap { shown.contains($0) ? $0 : nil } ?? shown.first
        return id.flatMap { Window.get(byId: $0) }
    }

    /// The tabs its bar shows: windows in the workspace's tiled tree, without any kept only while
    /// WinMuxX has briefly lost track of them.
    var shownWindowIds: [UInt32] { windowIds.filter { Window.get(byId: $0)?.parent is TilingContainer } }

    /// The group whose area and bar show this one: itself, or the one it is folded into.
    var barGroup: TabbedGroup { foldedInto ?? self }

    /// The tabs its bar shows, those of groups folded into it included.
    var barWindowIds: [UInt32] { shownWindowIds + foldedGroups.flatMap(\.shownWindowIds) }

    /// The window its area shows: the chosen tab of the group used last among it and those folded in.
    var displayedWindow: Window? {
        let member = displayedMember.flatMap { used in foldedGroups.first { $0 === used } } ?? self
        return member.activeWindow ?? activeWindow ?? foldedGroups.lazy.compactMap(\.activeWindow).first
    }

    /// The room its area needs: as much as the most demanding of its windows, shown or not, so no
    /// tab is ever squeezed below what its window allows.
    var minimumWindowSize: CGSize {
        let sizes = ([self] + foldedGroups).flatMap(\.shownWindowIds).compactMap { Window.get(byId: $0)?.minimumLayoutSize }
        return CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
    }
}

/// Groups side by side (columns) or stacked (rows), each sharing the area by its weight.
@MainActor
indirect enum TabbedLayout {
    case group(TabbedGroup)
    case split(Orientation, [TabbedLayout], [CGFloat])

    var groups: [TabbedGroup] {
        switch self {
            case .group(let group): [group]
            case .split(_, let children, _): children.flatMap(\.groups)
        }
    }

    /// Without the groups that hold no windows; a split left with one child becomes that child.
    func pruned() -> TabbedLayout? { pruned(keeping: { !$0.windowIds.isEmpty }) }

    /// Only the groups `keep` accepts, with splits collapsed to match. The groups themselves are shared.
    func pruned(keeping keep: (TabbedGroup) -> Bool) -> TabbedLayout? {
        switch self {
            case .group(let group): return keep(group) ? self : nil
            case .split(let orientation, let children, let weights):
                let kept = zip(children, weights).compactMap { child, weight in child.pruned(keeping: keep).map { ($0, weight) } }
                if kept.isEmpty { return nil }
                if kept.count == 1 { return kept[0].0 }
                return .split(orientation, kept.map(\.0), kept.map(\.1))
        }
    }

    /// Puts `newGroup` on `side` of `target`, sharing the target's area.
    func inserting(_ newGroup: TabbedGroup, beside target: TabbedGroup, on side: CardinalDirection) -> TabbedLayout {
        switch self {
            case .group(let group):
                guard group === target else { return self }
                let pair: [TabbedLayout] = side == .left || side == .up ? [.group(newGroup), self] : [self, .group(newGroup)]
                return .split(side.orientation, pair, [1, 1])
            case .split(let orientation, let children, let weights):
                // A same-direction split gains a sibling instead of nesting another split.
                if orientation == side.orientation, let index = children.firstIndex(where: { if case .group(let g) = $0 { g === target } else { false } }) {
                    var children = children, weights = weights
                    let at = side == .left || side == .up ? index : index + 1
                    children.insert(.group(newGroup), at: at)
                    weights.insert(weights[index], at: at)
                    return .split(orientation, children, weights)
                }
                return .split(orientation, children.map { $0.inserting(newGroup, beside: target, on: side) }, weights)
        }
    }

    /// Grows `group` by `delta` points along `axis` at the expense of its neighbour before or after
    /// it, in the nearest split of that direction. Nil when no split of that direction holds it.
    /// `strictSide` keeps to the neighbour on that side, leaving an outer boundary to the enclosing
    /// split, as dragging that edge means; otherwise the other side serves when there is none.
    func resizing(_ group: TabbedGroup, along axis: Orientation, by delta: CGFloat, againstNext: Bool, strictSide: Bool = false,
                  gap: CGFloat = 0) -> TabbedLayout? {
        guard case .split(let orientation, let children, let weights) = self,
              let index = children.firstIndex(where: { $0.groups.contains { $0 === group } }) else { return nil }
        if let inner = children[index].resizing(group, along: axis, by: delta, againstNext: againstNext, strictSide: strictSide, gap: gap) {
            var children = children
            children[index] = inner
            return .split(orientation, children, weights)
        }
        guard orientation == axis, children.count > 1 else { return nil }
        // Groups hidden while their windows are briefly missing have no size; the divider is between
        // shown neighbours, and hidden ones keep their share for when they return.
        let sizes = children.map { $0.extent(along: axis) }
        let shown = sizes.indices.filter { sizes[$0] > 0 }
        guard sizes[index] > 0, let position = shown.firstIndex(of: index) else { return nil }
        let onSide = againstNext ? shown.getOrNil(atIndex: position + 1) : shown.getOrNil(atIndex: position - 1)
        guard onSide != nil || !strictSide,
              let neighbor = onSide ?? (againstNext ? shown.getOrNil(atIndex: position - 1) : shown.getOrNil(atIndex: position + 1))
        else { return nil }
        // The weights restart from what is on screen, minimum sizes included: each shown child's size
        // plus its share of the gaps, as the tile allocator divides them. Points then move between the
        // two children only, so every other child keeps its size.
        var shares = weights
        for (order, child) in shown.enumerated() {
            shares[child] = sizes[child] + (order == 0 || order == shown.count - 1 ? gap / 2 : gap)
        }
        let scale = shown.map { shares[$0] }.reduce(0, +) / max(shown.map { weights[$0] }.reduce(0, +), 0.0001)
        for hidden in sizes.indices where sizes[hidden] <= 0 { shares[hidden] = weights[hidden] * scale }
        // Neither side goes below what its shown windows need, or the allocator would take the rest
        // from an uninvolved sibling.
        let floor = { (child: Int) in max(80, children[child].minimumExtent(horizontal: axis == .h, gap: CGSize(width: gap, height: gap))) }
        let change = max(min(delta, sizes[neighbor] - floor(neighbor)), floor(index) - sizes[index])
        shares[index] += change
        shares[neighbor] -= change
        return .split(orientation, children, shares)
    }

    /// The direction of the split nearest `group`, the one `resize smart` acts on.
    func nearestSplitOrientation(of group: TabbedGroup) -> Orientation? {
        guard case .split(let orientation, let children, _) = self,
              let child = children.first(where: { $0.groups.contains { $0 === group } }) else { return nil }
        return child.nearestSplitOrientation(of: group) ?? orientation
    }

    /// The size along `axis` that this part of the layout last took on screen.
    func extent(along axis: Orientation) -> CGFloat {
        let frames = groups.compactMap(\.lastFrame)
        guard !frames.isEmpty else { return 0 }
        return axis == .h
            ? (frames.map(\.maxX).max() ?? 0) - (frames.map(\.minX).min() ?? 0)
            : (frames.map(\.maxY).max() ?? 0) - (frames.map(\.minY).min() ?? 0)
    }

    /// Each group's area within `rect`: columns `gap.width` apart, rows `gap.height` apart. Groups
    /// share by weight, as tiles do, but never below what their shown window needs while space allows.
    func frames(in rect: Rect, gap: CGSize) -> [(TabbedGroup, Rect)] {
        switch self {
            case .group(let group): return [(group, rect)]
            case .split(let orientation, let children, let weights):
                let horizontal = orientation == .h
                let tiles = TileLayoutGeometry.calculate(TileLayoutInput(
                    origin: rect.topLeftCorner, size: CGSize(width: rect.width, height: rect.height), horizontal: horizontal,
                    innerGap: horizontal ? gap.width : gap.height,
                    weights: weights, minimumExtents: children.map { $0.minimumExtent(horizontal: horizontal, gap: gap) },
                    master: false, reversed: false))
                guard tiles.count == children.count else { return [] }
                return zip(children, tiles).flatMap { child, tile in
                    child.frames(in: Rect(topLeftX: tile.physical.minX, topLeftY: tile.physical.minY,
                                          width: tile.physical.width, height: tile.physical.height), gap: gap)
                }
        }
    }

    /// The least room along one axis that the shown windows, with their bars, need.
    func minimumExtent(horizontal: Bool, gap: CGSize) -> CGFloat {
        switch self {
            case .group(let group):
                // A folded group's windows count in the bar that shows them.
                if group.foldedInto != nil { return 0 }
                let minimum = group.minimumWindowSize
                return horizontal ? minimum.width : minimum.height + resolvedWindowTabBarHeight()
            case .split(let orientation, let children, _):
                let extents = children.filter { $0.groups.contains { $0.foldedInto == nil } }
                    .map { $0.minimumExtent(horizontal: horizontal, gap: gap) }
                return (orientation == .h) == horizontal
                    ? extents.reduce(0, +) + (horizontal ? gap.width : gap.height) * CGFloat(max(extents.count - 1, 0))
                    : extents.max() ?? 0
        }
    }
}

extension Workspace {
    /// The groups in reading order: left to right, top to bottom within each split.
    @MainActor var tabbedGroups: [TabbedGroup] { tabbedLayout?.groups ?? [] }

    @MainActor func tabbedGroup(containing windowId: UInt32) -> TabbedGroup? {
        tabbedGroups.first { $0.windowIds.contains(windowId) }
    }

    /// The group being worked in: the one holding the most recently focused tiled window.
    @MainActor var tabbedFocusedGroup: TabbedGroup? {
        rootTilingContainer.mostRecentWindowRecursive.flatMap { tabbedGroup(containing: $0.windowId) } ?? tabbedGroups.first
    }

    /// Brings the groups in line with the tiled windows: closed windows leave, new windows join
    /// the group being worked in, empty groups close, and the focused window becomes its group's
    /// shown tab.
    @MainActor func syncTabbedGroups() {
        let windows = rootTilingContainer.allLeafWindowsRecursive.map(\.windowId)
        let present = Set(windows)
        guard var layout = tabbedLayout else {
            tabbedLayout = windows.isEmpty ? nil : .group(TabbedGroup(windowIds: windows, activeWindowId: rootTilingContainer.mostRecentWindowRecursive?.windowId))
            return
        }
        // A window WinMuxX lost track of for a moment (Accessibility dropped it) keeps its place, so
        // its group and split come back with it. One that closed, or that WinMuxX still has
        // elsewhere (another workspace, floating), has left the group.
        for group in layout.groups {
            group.windowIds.removeAll { !present.contains($0) && !keepsTabbedPlace($0) }
            if let active = group.activeWindowId, !group.windowIds.contains(active) { group.activeWindowId = nil }
        }
        let assigned = Set(layout.groups.flatMap(\.windowIds))
        let newcomers = windows.filter { !assigned.contains($0) }
        if !newcomers.isEmpty {
            // The group being worked in; after a restore replaced the groups, the one holding the
            // window last focused here.
            let anchors = [lastTabbedFocusedWindowId, focus.windowOrNil?.windowId].compactMap { $0 }.filter { !newcomers.contains($0) }
            let target = lastTabbedGroup.flatMap { last in layout.groups.first { $0 === last } }
                ?? anchors.lazy.compactMap { id in layout.groups.first { $0.windowIds.contains(id) } }.first
                ?? layout.groups.first
            if let target {
                target.windowIds += newcomers
                // A window that opened and took focus is shown in the group it joined.
                if let focused = lastTabbedFocusedWindowId, newcomers.contains(focused) {
                    target.activeWindowId = focused
                    target.barGroup.displayedMember = target
                }
            } else {
                layout = .group(TabbedGroup(windowIds: newcomers, activeWindowId: lastTabbedFocusedWindowId.flatMap { newcomers.contains($0) ? $0 : nil }))
            }
        }
        tabbedLayout = layout.pruned()
        for group in tabbedGroups where group.activeWindowId == nil {
            group.activeWindowId = group.windowIds.first(where: present.contains)
        }
    }

    /// The groups to show: those holding at least one window in the tree now.
    @MainActor var visibleTabbedLayout: TabbedLayout? { tabbedLayout.flatMap(visibleTabbedLayout) }

    /// `layout` without the groups none of whose windows is in the tiled tree now.
    @MainActor func visibleTabbedLayout(_ layout: TabbedLayout) -> TabbedLayout? {
        let present = Set(rootTilingContainer.allLeafWindowsRecursive.map(\.windowId))
        return layout.pruned(keeping: { $0.windowIds.contains(where: present.contains) })
    }

    /// The groups that fit in `rect`, each sized as the layout gives it. When the windows' minimum
    /// sizes leave no room for every group, the group farthest from the one in use folds into its
    /// neighbour's bar, and so on until the rest fit. Only presentation changes: `tabbedLayout` and
    /// its groups stay, so a folded group returns when there is room again.
    @MainActor func foldedTabbedLayout(_ base: TabbedLayout? = nil, in rect: Rect, gap: CGSize) -> TabbedLayout? {
        // Groups folded last time fold again first, into the same bar, so choosing a folded tab
        // shows it there instead of reshuffling the bars under the pointer.
        let used = (lastTabbedFocusedWindowId ?? focus.windowOrNil?.windowId).flatMap { tabbedGroup(containing: $0) }
        let inUse = used?.barGroup
        var previous = tabbedGroups.compactMap { group in group.foldedInto.map { (group, $0) } }
        for group in tabbedGroups {
            group.foldedGroups = []
            group.foldedInto = nil
        }
        guard var layout = (base ?? tabbedLayout).flatMap(visibleTabbedLayout) else { return nil }
        while layout.minimumExtent(horizontal: true, gap: gap) > rect.width + 0.5
            || layout.minimumExtent(horizontal: false, gap: gap) > rect.height + 0.5
        {
            let groups = layout.groups
            guard groups.count > 1 else { break }
            let folded: TabbedGroup, host: TabbedGroup
            if let again = previous.firstIndex(where: { pair in groups.contains { $0 === pair.0 } && groups.contains { $0 === pair.1 } }) {
                (folded, host) = previous.remove(at: again)
            } else {
                let kept = inUse.flatMap { used in groups.firstIndex { $0 === used } } ?? 0
                let index = kept >= groups.count - 1 - kept ? 0 : groups.count - 1
                (folded, host) = (groups[index], groups[index == 0 ? 1 : groups.count - 2])
            }
            for member in [folded] + folded.foldedGroups { member.foldedInto = host }
            host.foldedGroups += [folded] + folded.foldedGroups
            folded.foldedGroups = []
            guard let rest = layout.pruned(keeping: { $0 !== folded }) else { break }
            layout = rest
        }
        // Whichever bar now shows the group last used here shows it, even after its host changed.
        if let used { used.barGroup.displayedMember = used }
        return layout
    }

    /// Whether a window out of the tiled tree keeps its tab: while WinMuxX briefly lost track of it,
    /// or while macOS holds it minimized, hidden with its app, or in native fullscreen. A window
    /// that closed, floats, or went to another workspace has left.
    @MainActor private func keepsTabbedPlace(_ windowId: UInt32) -> Bool {
        guard let window = Window.get(byId: windowId) else { return windowServerStillHas(windowId) }
        if window.parent is TilingContainer || window.parent is Workspace { return false }
        return window.nodeWorkspace == nil || window.nodeWorkspace === self
    }

    /// Moves a tab to `index` among the tabs its group's bar shows.
    @MainActor func reorderTabbedTab(_ windowId: UInt32, toIndex index: Int) -> Bool {
        guard let group = tabbedGroup(containing: windowId) else { return false }
        let shown = group.shownWindowIds
        guard let from = shown.firstIndex(of: windowId) else { return false }
        let target = max(0, min(index, shown.count - 1))
        if target == from { return true }
        // Place it beside the tab now at that position, so tabs kept out of view keep theirs.
        let anchor = shown[target]
        group.windowIds.removeAll { $0 == windowId }
        guard let anchorIndex = group.windowIds.firstIndex(of: anchor) else { return false }
        group.windowIds.insert(windowId, at: target > from ? anchorIndex + 1 : anchorIndex)
        return true
    }

    /// Moves a tab into `target`, at the end or at `index`, and shows it there.
    @MainActor func moveTabbedTab(_ windowId: UInt32, into target: TabbedGroup, at index: Int? = nil) -> Bool {
        guard let source = tabbedGroup(containing: windowId), tabbedGroups.contains(where: { $0 === target }) else { return false }
        if source === target { return index.map { reorderTabbedTab(windowId, toIndex: $0) } ?? false }
        source.windowIds.removeAll { $0 == windowId }
        if source.activeWindowId == windowId { source.activeWindowId = source.windowIds.first }
        target.windowIds.insert(windowId, at: min(index ?? target.windowIds.count, target.windowIds.count))
        target.activeWindowId = windowId
        if lastTabbedFocusedWindowId == windowId { lastTabbedGroup = target }
        tabbedLayout = tabbedLayout?.pruned()
        return true
    }

    /// Puts a tab at `index` among the other tabs `bar`'s bar shows, as dropping it there does: into
    /// the group of the tab it lands before, or after the last tab, staying in its own group when it
    /// lands beside one of its own tabs. Shows it there.
    @MainActor func insertTabbedTab(_ windowId: UInt32, intoBarOf bar: TabbedGroup, at index: Int) -> Bool {
        guard let source = tabbedGroup(containing: windowId) else { return false }
        // Put back where it was, it stays: no group changes hands for a gesture that moved nothing.
        if source.barGroup === bar, bar.barWindowIds.firstIndex(of: windowId) == index {
            source.activeWindowId = windowId
            return true
        }
        let tabs = bar.barWindowIds.filter { $0 != windowId }
        let before = tabs.getOrNil(atIndex: index - 1), after = tabs.getOrNil(atIndex: index)
        // Before `after`, or else after `before`; its own group's neighbour wins when there are two.
        let anchor: (id: UInt32, after: Bool)? = if let after, !(before.map { source.windowIds.contains($0) } ?? false)
            || source.windowIds.contains(after) {
            (after, false)
        } else {
            (before ?? tabs.last).map { ($0, true) }
        }
        let group = anchor.flatMap { tabbedGroup(containing: $0.id) } ?? bar
        var ids = group.windowIds.filter { $0 != windowId }
        let position = anchor.flatMap { anchor in ids.firstIndex(of: anchor.id).map { anchor.after ? $0 + 1 : $0 } } ?? ids.count
        if source === group {
            ids.insert(windowId, at: position)
            group.windowIds = ids
            group.activeWindowId = windowId
            return true
        }
        return moveTabbedTab(windowId, into: group, at: position)
    }

    /// Opens a new group on `side` of `target` holding the tab, as dropping it on that edge does.
    @MainActor func moveTabbedTabToNewGroup(_ windowId: UInt32, beside target: TabbedGroup, on side: CardinalDirection) -> Bool {
        guard let source = tabbedGroup(containing: windowId), let layout = tabbedLayout,
              !(source === target && source.windowIds.count == 1) else { return false }
        source.windowIds.removeAll { $0 == windowId }
        if source.activeWindowId == windowId { source.activeWindowId = source.windowIds.first }
        let group = TabbedGroup(windowIds: [windowId])
        tabbedLayout = layout.inserting(group, beside: target, on: side).pruned()
        if lastTabbedFocusedWindowId == windowId { lastTabbedGroup = group }
        return true
    }

    /// Moves every tab of `group` into `target`, after its own tabs, showing the tab `group` showed.
    @MainActor func mergeTabbedGroup(_ group: TabbedGroup, into target: TabbedGroup) -> Bool {
        guard group !== target, tabbedGroups.contains(where: { $0 === group }), tabbedGroups.contains(where: { $0 === target })
        else { return false }
        target.windowIds += group.windowIds
        target.activeWindowId = group.activeWindowId ?? target.activeWindowId
        if lastTabbedGroup === group { lastTabbedGroup = target }
        group.windowIds = []
        tabbedLayout = tabbedLayout?.pruned()
        return true
    }

    /// Gathers every tab into `group`, leaving one group again.
    @MainActor func mergeAllTabbedGroups(into group: TabbedGroup) -> Bool {
        let others = tabbedGroups.filter { $0 !== group }
        guard tabbedGroups.contains(where: { $0 === group }), !others.isEmpty else { return false }
        let active = group.activeWindowId
        for other in others { _ = mergeTabbedGroup(other, into: group) }
        group.activeWindowId = active ?? group.windowIds.first
        return true
    }

    /// Moves the whole of `group`, all its tabs, to `side` of `target`.
    @MainActor func moveTabbedGroup(_ group: TabbedGroup, beside target: TabbedGroup, on side: CardinalDirection) -> Bool {
        guard group !== target, tabbedGroups.contains(where: { $0 === target }),
              let rest = tabbedLayout?.pruned(keeping: { $0 !== group && !$0.windowIds.isEmpty }) else { return false }
        tabbedLayout = rest.inserting(group, beside: target, on: side)
        return true
    }

    /// Resizes the tab group holding `window`, as `resize` and dragging a window's edge do in
    /// other arrangements. Only the groups' shares change; the tree beneath stays as it was.
    @MainActor func resizeTabbedGroup(of window: Window, along axis: Orientation, by delta: CGFloat, againstNext: Bool = true,
                                      strictSide: Bool = false) -> Bool {
        guard let layout = tabbedLayout, let resized = tabbedLayout(layout, resizingGroupOf: window, along: axis, by: delta,
                                                                    againstNext: againstNext, strictSide: strictSide) else { return false }
        tabbedLayout = resized
        return true
    }

    /// `layout` with the group of `window` resized, leaving the workspace as it is, or nil when
    /// nothing can give way.
    @MainActor func tabbedLayout(_ layout: TabbedLayout, resizingGroupOf window: Window, along axis: Orientation,
                                 by delta: CGFloat, againstNext: Bool, strictSide: Bool) -> TabbedLayout? {
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspaceMonitor).inner
        let gap = CGFloat(axis == .h ? gaps.horizontal : gaps.vertical)
        guard let group = tabbedGroup(containing: window.windowId)?.barGroup else { return nil }
        return layout.resizing(group, along: axis, by: delta, againstNext: againstNext, strictSide: true, gap: gap)
            ?? (strictSide ? nil : layout.resizing(group, along: axis, by: delta, againstNext: againstNext, gap: gap))
    }

    /// The group whose last area lies on `direction`'s side of `group`, nearest first.
    @MainActor func tabbedGroup(beside group: TabbedGroup, _ direction: CardinalDirection) -> TabbedGroup? {
        let group = group.barGroup
        guard let from = group.lastFrame else { return nil }
        return tabbedGroups.compactMap { other -> (TabbedGroup, CGFloat)? in
            guard other !== group, let to = other.lastFrame else { return nil }
            let (gap, overlaps): (CGFloat, Bool) = switch direction {
                case .right: (to.minX - from.maxX, to.minY < from.maxY && to.maxY > from.minY)
                case .left: (from.minX - to.maxX, to.minY < from.maxY && to.maxY > from.minY)
                case .down: (to.minY - from.maxY, to.minX < from.maxX && to.maxX > from.minX)
                case .up: (from.minY - to.maxY, to.minX < from.maxX && to.maxX > from.minX)
            }
            return overlaps && gap > -1 ? (other, gap) : nil
        }.min(by: { $0.1 < $1.1 })?.0
    }
}

@MainActor
private func windowServerStillHas(_ windowId: UInt32) -> Bool {
    !isUnitTest && winmux_window_exists(windowId)
}

extension Window {
    /// A tab kept while macOS holds its window goes with its group to `target`: native fullscreen
    /// and hidden windows to that workspace's containers, and each returns there when macOS lets go.
    @MainActor func transferRetainedTabbedState(to target: Workspace) {
        switch parent?.nodeCases {
            case .macosFullscreenWindowsContainer:
                bind(to: target.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
            case .macosHiddenAppsWindowsContainer:
                bind(to: target.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
            default: break
        }
        if case .macos(let kind, _) = layoutReason { layoutReason = .macos(prevParentKind: kind, prevWorkspaceName: target.name) }
    }

    /// Focusing a window of a Tabbed workspace shows it in its group. Only real focus does this:
    /// restoring a tree rebinds windows in order without anyone choosing them.
    @MainActor func noteTabbedFocus() {
        guard let workspace = nodeWorkspace, workspace.arrangement == .tabbed, parent is TilingContainer else { return }
        workspace.lastTabbedFocusedWindowId = windowId
        guard let group = workspace.tabbedGroup(containing: windowId) else { return }
        group.activeWindowId = windowId
        group.barGroup.displayedMember = group
        workspace.lastTabbedGroup = group
    }
}

/// The saved form of a Tabbed workspace's groups, by window ID.
indirect enum FrozenTabbedLayout: Codable, Equatable, Sendable {
    case group(windowIds: [UInt32], active: UInt32?)
    case split(orientation: Orientation, children: [FrozenTabbedLayout], weights: [CGFloat])

    @MainActor init(_ layout: TabbedLayout) {
        switch layout {
            case .group(let group): self = .group(windowIds: group.windowIds, active: group.activeWindowId)
            case .split(let orientation, let children, let weights):
                self = .split(orientation: orientation, children: children.map(FrozenTabbedLayout.init), weights: weights)
        }
    }

    /// The live layout, with saved window IDs mapped to the windows restored for them. Windows not
    /// back yet keep their saved IDs, so one returning later rejoins its group; IDs WindowServer
    /// no longer has are dropped at the next sync.
    @MainActor func restored(_ windowsById: [UInt32: Window]) -> TabbedLayout? {
        switch self {
            case .group(let ids, let active):
                return .group(TabbedGroup(windowIds: ids.map { windowsById[$0]?.windowId ?? $0 },
                                          activeWindowId: active.map { windowsById[$0]?.windowId ?? $0 }))
            case .split(let orientation, let children, let weights):
                let kept = zip(children, weights).compactMap { child, weight in child.restored(windowsById).map { ($0, weight) } }
                return TabbedLayout.split(orientation, kept.map(\.0), kept.map(\.1)).pruned()
        }
    }
}

extension FrozenContainer {
    /// The windows of each side-by-side tab saved by build 322, outermost first.
    var legacySideBySideTabs: [[UInt32]] {
        if isTabbedSplit == true { return [collectWindowIds()] }
        return children.flatMap { child -> [[UInt32]] in
            if case .container(let container) = child { return container.legacySideBySideTabs }
            return []
        }
    }

    private func collectWindowIds() -> [UInt32] {
        children.flatMap { child -> [UInt32] in
            switch child {
                case .window(let window): [window.id]
                case .container(let container): container.collectWindowIds()
            }
        }
    }
}

/// Groups for state saved before tab groups existed: each side-by-side tab of build 322 becomes
/// columns of its own windows beside the group holding everything else.
@MainActor
func migratedTabbedLayout(from root: FrozenContainer, _ windowsById: [UInt32: Window], allWindows: [UInt32]) -> TabbedLayout? {
    let sideBySide = root.legacySideBySideTabs.map { $0.compactMap { windowsById[$0]?.windowId } }.filter { $0.count > 1 }
    guard !sideBySide.isEmpty else { return nil }
    let grouped = Set(sideBySide.flatMap { $0 })
    let rest = allWindows.filter { !grouped.contains($0) }
    let columns = ([rest] + sideBySide.flatMap { $0.map { [$0] } }).filter { !$0.isEmpty }
    return TabbedLayout.split(.h, columns.map { .group(TabbedGroup(windowIds: $0)) }, columns.map { _ in 1 }).pruned()
}
