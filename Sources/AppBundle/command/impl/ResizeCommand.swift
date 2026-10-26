import AppKit
import Common

struct ResizeCommand: Command {
    let args: ResizeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        if runtime.workspaceBackend.kind == .native,
           target.windowOrNil?.parentsWithSelf.contains(where: { node in
               guard let container = node as? TilingContainer, container.layout == .dwindle else { return false }
               return container.frameLayoutChildren.count != container.children.count
           }) == true {
            return io.err("Native Dwindle resize with concealed siblings is not supported yet; restore those windows first")
        }

        if target.workspace.arrangement == .scrolling, let window = target.windowOrNil {
            switch args.dimension.val {
                case .width, .smart:
                    return resizeScrollingColumn(window, units: args.units.val, workspace: target.workspace, io: io)
                case .height, .smartOpposite:
                    break
            }
        }

        if let window = target.windowOrNil, let workspace = window.nodeWorkspace,
           singleWindowWidthTarget(in: workspace) === window,
           args.dimension.val == .width || args.dimension.val == .smart {
            let current = workspaceTilingRect(workspace).width
            let width: CGFloat = switch args.units.val {
                case .set(let value): CGFloat(value)
                case .add(let value): current + CGFloat(value)
                case .subtract(let value): current - CGFloat(value)
            }
            return applySingleWindowManualResize(window, width: max(minimumTiledResizeWeight, width))
        }

        let candidates: [WindowResizeCommandTarget] = target.windowOrNil?.parentsWithSelf.flatMap { node -> [WindowResizeCommandTarget] in
            guard let parent = node.parent as? TilingContainer else { return [] }
            if target.workspace.arrangement != .dwindle, parent === target.workspace.rootTilingContainer { return [] }
            switch parent.layout {
                case .tiles, .master: return [.tiles(node, parent)]
                case .dwindle: return node.dwindleResizeTargets().map(WindowResizeCommandTarget.dwindle)
                case .tabGroup, .stacked: return []
            }
        } ?? []
        let selected: WindowResizeCommandTarget?
        switch args.dimension.val {
            case .width: selected = candidates.first { $0.orientation == .h }
            case .height: selected = candidates.first { $0.orientation == .v }
            case .smart: selected = candidates.first
            case .smartOpposite:
                selected = candidates.first { $0.orientation == candidates.first?.orientation.opposite }
        }
        guard let selected else {
            guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
            if target.workspace.resizeMasterPane(window, dimension: args.dimension.val, units: args.units.val) { return true }
            if window.parent is TilingContainer {
                io.out("resize: nothing to do")
                return true
            }
            return io.err("resize command doesn't support floating windows yet https://github.com/nikitabobko/WinMux/issues/9")
        }
        if case .dwindle(let split) = selected {
            if !split.resize(args.units.val) { io.out("resize: nothing to do") }
            return true
        }
        guard case .tiles(let node, let parent) = selected else { return false }
        let orientation = parent.orientation
        let requestedDiff: CGFloat = switch args.units.val {
            case .set(let unit): CGFloat(unit) - node.getWeight(orientation)
            case .add(let unit): CGFloat(unit)
            case .subtract(let unit): -CGFloat(unit)
        }

        let siblings = parent.children.filter { $0 != node }
        guard !siblings.isEmpty else { io.out("resize: nothing to do"); return true }
        let siblingMultiplier = -CGFloat(1).div(siblings.count).orDie()
        let diff = constrainedTiledResizeDiff(
            requestedDiff,
            adjustments: [TiledResizeAdjustment(weight: node.getWeight(orientation), multiplier: 1)] +
                siblings.map { TiledResizeAdjustment(weight: $0.getWeight(orientation), multiplier: siblingMultiplier) },
        )
        if abs(diff - requestedDiff) > 0.01 {
            let blockedAxis = orientation == .h ? "width" : "height"
            let blocked = parent.allLeafWindowsRecursive.compactMap { $0 as? MacWindow }.first {
                orientation == .h ? $0.minimumLayoutSize.width > 0 : $0.minimumLayoutSize.height > 0
            }
            if let blocked {
                MinimumSizeNoticePanel.shared.show(appName: blocked.macApp.name ?? blocked.macApp.rawAppBundleId ?? "Application",
                                                   dimension: blockedAxis, minimum: blocked.minimumLayoutSize)
            }
        }
        let childDiff = diff.div(siblings.count).orDie()
        siblings
            .forEach { $0.setWeight(parent.orientation, $0.getWeight(parent.orientation) - childDiff) }

        node.setWeight(orientation, node.getWeight(orientation) + diff)
        return true
    }
}

@MainActor
private func resizeScrollingColumn(_ window: Window, units: ResizeCmdArgs.Units, workspace: Workspace, io: CmdIo) -> Bool {
    let group = window.topLevelWorkspaceGroup
    guard let column = workspace.scrollingMetrics.columns.first(where: { $0.node === group }) else { return io.err("The focused window has no scrolling column") }
    let metrics = workspace.scrollingMetrics
    let lower = column.node.minimumLayoutExtent(along: .h, rect: workspaceTilingRect(workspace))
    let requested: CGFloat = switch units {
        case .set(let value): CGFloat(value)
        case .add(let value): column.width + CGFloat(value)
        case .subtract(let value): column.width - CGFloat(value)
    }
    let maximum = max(metrics.areaWidth - column.frameStartInset - column.frameEndInset, lower)
    let actual = min(max(requested, lower), maximum)
    if requested + 1 < lower, let blocked = group.allLeafWindowsRecursive.compactMap({ $0 as? MacWindow }).first(where: { $0.minimumLayoutSize.width > 0 }) {
        MinimumSizeNoticePanel.shared.show(appName: blocked.macApp.name ?? blocked.macApp.rawAppBundleId ?? "Application",
                                           dimension: "width", minimum: blocked.minimumLayoutSize)
    }
    if abs(actual - column.width) < 0.5 {
        io.out("resize: nothing to do")
        return true
    }
    group.scrollingColumnWidth = min(max((actual + column.frameStartInset + column.frameEndInset) / max(metrics.areaWidth, 1), 0.1), 1)
    scheduleRefreshSession(.globalObserver("resizeScrollingColumn"))
    return true
}
