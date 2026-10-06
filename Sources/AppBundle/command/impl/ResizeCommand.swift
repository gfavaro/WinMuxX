import AppKit
import Common

struct ResizeCommand: Command {
    let args: ResizeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }

        let candidates: [WindowResizeCommandTarget] = target.windowOrNil?.parentsWithSelf.flatMap { node -> [WindowResizeCommandTarget] in
            guard let parent = node.parent as? TilingContainer else { return [] }
            switch parent.layout {
                case .tiles: return [.tiles(node, parent)]
                case .dwindle: return node.dwindleResizeTargets().map(WindowResizeCommandTarget.dwindle)
                case .tabGroup: return []
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
            return io.err("resize command doesn't support floating windows yet https://github.com/nikitabobko/WinMux/issues/9")
        }
        if case .dwindle(let split) = selected { return split.resize(args.units.val) }
        guard case .tiles(let node, let parent) = selected else { return false }
        let orientation = parent.orientation
        let requestedDiff: CGFloat = switch args.units.val {
            case .set(let unit): CGFloat(unit) - node.getWeight(orientation)
            case .add(let unit): CGFloat(unit)
            case .subtract(let unit): -CGFloat(unit)
        }

        let siblings = parent.children.filter { $0 != node }
        guard !siblings.isEmpty else { return false }
        let siblingMultiplier = -CGFloat(1).div(siblings.count).orDie()
        let diff = constrainedTiledResizeDiff(
            requestedDiff,
            adjustments: [TiledResizeAdjustment(weight: node.getWeight(orientation), multiplier: 1)] +
                siblings.map { TiledResizeAdjustment(weight: $0.getWeight(orientation), multiplier: siblingMultiplier) },
        )
        let childDiff = diff.div(siblings.count).orDie()
        siblings
            .forEach { $0.setWeight(parent.orientation, $0.getWeight(parent.orientation) - childDiff) }

        node.setWeight(orientation, node.getWeight(orientation) + diff)
        return true
    }
}
