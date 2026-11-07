import AppKit
import Common

struct SplitCommand: Command {
    let args: SplitCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        // In a Tabbed workspace the tab opens in a new tab group: a column, or a row below.
        if target.workspace.arrangement == .tabbed, let window = target.windowOrNil, window.parent is TilingContainer {
            let workspace = target.workspace
            workspace.syncTabbedGroups()
            guard let group = workspace.tabbedGroup(containing: window.windowId) else { return false }
            let orientation: Orientation = switch args.arg.val {
                case .vertical: .v
                case .horizontal: .h
                case .opposite: (workspace.presentedTabbedLayout?.nearestSplitOrientation(of: group.barGroup)
                    ?? workspace.tabbedLayout?.nearestSplitOrientation(of: group) ?? .v).opposite
            }
            if !workspace.moveTabbedTabToNewGroup(window.windowId, beside: group, on: orientation == .h ? .right : .down) {
                io.out("split: nothing to do")
            }
            return true
        }
        if config.enableNormalizationFlattenContainers {
            return io.err("'split' has no effect when 'enable-normalization-flatten-containers' normalization enabled. My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.")
        }
        guard let window = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        guard let parent = window.parent else { return false }
        switch parent.cases {
            case .workspace:
                // Nothing to do for floating and macOS native fullscreen windows
                return io.err("Can't split floating windows")
            case .tilingContainer(let parent):
                let orientation: Orientation = switch args.arg.val {
                    case .vertical: .v
                    case .horizontal: .h
                    case .opposite: parent.orientation.opposite
                }
                if parent.children.count == 1 {
                    parent.changeOrientation(orientation)
                } else {
                    let data = window.unbindFromParent()
                    let newParent = TilingContainer(
                        parent: parent,
                        adaptiveWeight: data.adaptiveWeight,
                        orientation,
                        .tiles,
                        index: data.index,
                    )
                    window.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
                }
                return true
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
                return io.err("Can't split macos fullscreen, minimized windows and windows of hidden apps. This behavior may change in the future")
            case .macosPopupWindowsContainer:
                return false // Impossible
        }
    }
}
