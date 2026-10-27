import AppKit
import Common

struct ScrollingMinimapCommand: Command {
    let args: ScrollingMinimapCmdArgs
    let shouldResetClosedWindowsCache = false
    let isPresentation = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard target.workspace.arrangement == .scrolling else { return io.err("scrolling-minimap requires a scrolling workspace") }
        guard config.scrolling.minimapEnabled else { return io.err("The scrolling minimap is disabled in configuration") }
        guard !target.workspace.workspaceLayoutUnits.isEmpty else { return io.err("The scrolling workspace has no groups") }
        if WorkspaceScrollingMinimap.shared.isExplicitlyOpen {
            WorkspaceScrollingMinimap.shared.dismiss()
            return true
        }
        return WorkspaceScrollingMinimap.shared.show(target.workspace, explicitly: true) || io.err("The scrolling minimap is unavailable during this interaction")
    }
}

struct ScrollingCenterCommand: Command {
    let args: ScrollingCenterCmdArgs
    let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard target.workspace.arrangement == .scrolling else { return io.err("scrolling-center requires a scrolling workspace") }
        target.workspace.centerFocusedScrollingColumn()
        return true
    }
}

struct ScrollingWidthCommand: Command {
    let args: ScrollingWidthCmdArgs
    let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        guard workspace.arrangement == .scrolling else { return io.err("scrolling-width requires a scrolling workspace") }
        guard let window = target.windowOrNil,
              let column = workspace.workspaceLayoutUnits.first(where: { $0 === window.topLevelWorkspaceGroup }) else {
            return io.err(noWindowIsFocused)
        }
        let presets = config.scrolling.widthPresets
        guard !presets.isEmpty else { return io.err("[scrolling].width-presets must not be empty") }
        let current = column.scrollingColumnWidth ?? config.scrolling.columnWidth
        let next: Double
        switch args.action.val {
            case .full: next = 1
            case .next:
                next = presets.first(where: { $0 > current }) ?? presets[0]
            case .previous:
                next = presets.last(where: { $0 < current }) ?? presets[presets.count - 1]
        }
        column.scrollingColumnWidth = CGFloat(next)
        workspace.lastScrollingFocusWindowId = nil
        scheduleRefreshSession(.globalObserver("scrollingWidth"))
        return true
    }
}

extension Workspace {
    /// Moves a strip column, by identity, to an index among the strip's columns.
    @MainActor
    func moveScrollingColumn(_ id: ObjectIdentifier, toStripIndex index: Int) {
        let units = scrollingStripUnits
        guard let column = units.first(where: { ObjectIdentifier($0) == id }), units.indices.contains(index) else { return }
        let destination = units[index]
        let root = rootTilingContainer
        guard column.parent === root, destination !== column, let target = root.children.firstIndex(where: { $0 === destination }) else { return }
        let binding = column.unbindFromParent()
        column.bind(to: root, adaptiveWeight: binding.adaptiveWeight, index: target)
        lastScrollingFocusWindowId = nil
        scheduleRefreshSession(.globalObserver("scrollingMove"))
    }

    /// The strip column at a place: 1-based, first or last. A pinned column is not on the strip.
    @MainActor
    func scrollingColumn(at position: ScrollingColumnPosition) -> (index: Int, node: TreeNode)? {
        let units = scrollingStripUnits
        let index: Int? = switch position {
            case .first: units.isEmpty ? nil : 0
            case .last: units.isEmpty ? nil : units.count - 1
            case .index(let n): units.indices.contains(n - 1) ? n - 1 : nil
        }
        return index.map { ($0, units[$0]) }
    }
}

struct ScrollingFocusCommand: Command {
    let args: ScrollingFocusCmdArgs
    let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        guard workspace.arrangement == .scrolling else { return io.err("scrolling-focus requires a scrolling workspace") }
        guard let (_, column) = workspace.scrollingColumn(at: args.position.val) else {
            return io.err("The scrolling strip has no column there")
        }
        guard let window = column.mostRecentWindowRecursive else { return io.err("That column has no window") }
        return window.focusWindow()
    }
}

struct ScrollingMoveCommand: Command {
    let args: ScrollingMoveCmdArgs
    let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        guard workspace.arrangement == .scrolling else { return io.err("scrolling-move requires a scrolling workspace") }
        guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        let column = window.topLevelWorkspaceGroup
        guard column !== workspace.pinnedScrollingColumn else { return io.err("A pinned column has no place on the strip; unpin it first") }
        guard let (_, destination) = workspace.scrollingColumn(at: args.position.val) else {
            return io.err("The scrolling strip has no column there")
        }
        guard let index = workspace.scrollingStripUnits.firstIndex(where: { $0 === destination }) else { return true }
        workspace.moveScrollingColumn(ObjectIdentifier(column), toStripIndex: index)
        return true
    }
}

struct ScrollingPinCommand: Command {
    let args: ScrollingPinCmdArgs
    let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        guard workspace.arrangement == .scrolling else { return io.err("scrolling-pin requires a scrolling workspace") }
        guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        let column = window.topLevelWorkspaceGroup
        guard column.parent === workspace.rootTilingContainer else { return io.err("Only a tiled column can be pinned") }
        if workspace.pinnedScrollingColumn === column, workspace.scrollingPinSide == args.side.val {
            workspace.scrollingPinnedNode = nil
        } else {
            guard workspace.workspaceLayoutUnits.count > 1 else { return io.err("Pinning needs another column to scroll beside it") }
            workspace.scrollingPinnedNode = column
            workspace.scrollingPinSide = args.side.val
        }
        workspace.lastScrollingFocusWindowId = nil
        scheduleRefreshSession(.globalObserver("scrollingPin"))
        return true
    }
}
