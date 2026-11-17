import AppKit
import Common

private let notScrolling = "The workspace does not use the Scrolling layout"

extension Workspace {
    /// The strip column at a place: 1-based, first or last.
    @MainActor
    func scrollingColumn(at position: ScrollingColumnPosition) -> TreeNode? {
        let units = workspaceLayoutUnits
        return switch position {
            case .first: units.first
            case .last: units.last
            case .index(let n): units.getOrNil(atIndex: n - 1)
        }
    }
}

struct ScrollingFocusCommand: Command {
    let args: ScrollingFocusCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard target.workspace.arrangement == .scrolling else { return io.err(notScrolling) }
        guard let column = target.workspace.scrollingColumn(at: args.position.val) else {
            return io.err("The Scrolling strip has no column there")
        }
        guard let window = column.mostRecentWindowRecursive else { return io.err("That column has no window") }
        return window.focusWindow()
    }
}

struct ScrollingMoveCommand: Command {
    let args: ScrollingMoveCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        guard workspace.arrangement == .scrolling else { return io.err(notScrolling) }
        guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        let column = window.topLevelWorkspaceGroup
        guard let destination = workspace.scrollingColumn(at: args.position.val) else {
            return io.err("The Scrolling strip has no column there")
        }
        let parent = workspace.arrangementGroupParent
        guard destination !== column, column.parent === parent,
              let index = parent.children.firstIndex(where: { $0 === destination }) else { return true }
        let binding = column.unbindFromParent()
        column.bind(to: parent, adaptiveWeight: binding.adaptiveWeight, index: index)
        workspace.lastScrollingFocusWindowId = nil
        return true
    }
}

struct ScrollingCenterCommand: Command {
    let args: ScrollingCenterCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard target.workspace.arrangement == .scrolling else { return io.err(notScrolling) }
        target.workspace.centerFocusedScrollingColumn()
        return true
    }
}

struct ScrollingPanCommand: Command {
    let args: ScrollingPanCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        guard workspace.arrangement == .scrolling else { return io.err(notScrolling) }
        let metrics = workspace.scrollingMetrics
        guard !metrics.columns.isEmpty else { return io.err("The Scrolling strip has no columns") }
        let original = metrics.clampedOffset(workspace.scrollingOffset)
        switch args.direction.val {
            case .left: workspace.scrollingOffset = metrics.clampedOffset(original - metrics.areaWidth / 2)
            case .right: workspace.scrollingOffset = metrics.clampedOffset(original + metrics.areaWidth / 2)
            case .focus:
                guard let window = target.windowOrNil,
                      let column = metrics.columns.first(where: { $0.node === window.topLevelWorkspaceGroup }) else {
                    return io.err(noWindowIsFocused)
                }
                workspace.scrollingOffset = metrics.revealedOffset(for: column, current: original)
        }
        // Panning keeps focus where it is: the next layout must not scroll back to it.
        if let window = target.windowOrNil { workspace.lastScrollingFocusWindowId = window.windowId }
        WorkspaceScrollingMinimap.shared.show(workspace)
        workspace.captureScrollingViewportAnchor(using: workspace.scrollingMetrics)
        return true
    }
}

struct ScrollingWidthCommand: Command {
    let args: ScrollingWidthCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        guard workspace.arrangement == .scrolling else { return io.err(notScrolling) }
        guard let window = target.windowOrNil,
              let column = workspace.workspaceLayoutUnits.first(where: { $0 === window.topLevelWorkspaceGroup }) else {
            return io.err(noWindowIsFocused)
        }
        let presets = config.scrolling.widthPresets
        let current = column.scrollingColumnWidth ?? config.scrolling.columnWidth
        let next: Double = switch args.target.val {
            case .share(let share): share
            case .action(.full): 1
            case .action(.next): presets.first(where: { $0 > current + 0.001 }) ?? presets[0]
            case .action(.previous): presets.last(where: { $0 < current - 0.001 }) ?? presets[presets.count - 1]
        }
        column.scrollingColumnWidth = CGFloat(next)
        // The resized column is scrolled into view again.
        workspace.lastScrollingFocusWindowId = nil
        return true
    }
}

struct ScrollingMinimapCommand: Command {
    let args: ScrollingMinimapCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false
    var isPresentation: Bool { true }

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard target.workspace.arrangement == .scrolling else { return io.err(notScrolling) }
        guard config.scrolling.minimapEnabled else { return io.err("The Scrolling minimap is off in Settings") }
        guard !target.workspace.workspaceLayoutUnits.isEmpty else { return io.err("The Scrolling strip has no columns") }
        if WorkspaceScrollingMinimap.shared.isExplicitlyOpen {
            WorkspaceScrollingMinimap.shared.dismiss()
            return true
        }
        return WorkspaceScrollingMinimap.shared.show(target.workspace, explicitly: true)
            || io.err("The Scrolling minimap is unavailable during this interaction")
    }
}

struct ScrollingPinCommand: Command {
    let args: ScrollingPinCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        guard workspace.arrangement == .scrolling else { return io.err(notScrolling) }
        guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        let column = window.topLevelWorkspaceGroup
        guard workspace.workspaceLayoutUnits.contains(where: { $0 === column }) else { return io.err("Only a tiled column can be pinned") }
        if workspace.pinnedScrollingColumn === column, workspace.scrollingPinSide == args.side.val {
            workspace.scrollingPinnedNode = nil
        } else {
            guard workspace.workspaceLayoutUnits.count > 1 else { return io.err("Pinning needs another column to scroll beside it") }
            workspace.scrollingPinnedNode = column
            workspace.scrollingPinSide = args.side.val
        }
        workspace.lastScrollingFocusWindowId = nil
        return true
    }
}
