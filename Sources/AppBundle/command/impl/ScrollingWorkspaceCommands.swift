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
