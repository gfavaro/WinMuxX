import AppKit
import Common

struct LayoutCommand: Command {
    let args: LayoutCmdArgs
    /*conforms*/ var shouldResetClosedWindowsCache: Bool { !args.forNextDetectedWindow }

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        if args.forNextDetectedWindow {
            guard args.toggleBetween.val.count == 1,
                  let layout = args.toggleBetween.val.first, layout == .floating || layout == .tiling else {
                return io.err("--for-next-detected-window allows exactly one tiling|floating argument")
            }
            layoutForNextDetectedWindow = layout
            return true
        }
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        let targetDescription = nextLayout(in: args.toggleBetween.val, matching: { window.matchesDescription($0) })
        if window.matchesDescription(targetDescription) { return false }
        if target.workspace.arrangement == .scrolling,
           window.parent === target.workspace.rootTilingContainer,
           targetDescription != .floating, targetDescription != .tiling {
            let parent = window.parent as! TilingContainer
            let binding = window.unbindFromParent()
            let wrapper = TilingContainer(parent: parent, adaptiveWeight: binding.adaptiveWeight,
                                          parent.orientation, .tiles, index: binding.index)
            wrapper.scrollingColumnWidth = window.scrollingColumnWidth
            window.scrollingColumnWidth = nil
            window.bind(to: wrapper, adaptiveWeight: WEIGHT_AUTO, index: 0)
        }
        switch targetDescription {
            case .hTabGroup:
                return changeTilingLayout(io, targetLayout: .tabGroup, targetOrientation: .h, window: window)
            case .vTabGroup:
                return changeTilingLayout(io, targetLayout: .tabGroup, targetOrientation: .v, window: window)
            case .h_tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: .h, window: window)
            case .v_tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: .v, window: window)
            case .tabGroup:
                return changeTilingLayout(io, targetLayout: .tabGroup, targetOrientation: nil, window: window)
            case .stacked:
                return changeTilingLayout(io, targetLayout: .stacked, targetOrientation: nil, window: window)
            case .tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: nil, window: window)
            case .auto:
                guard let parent = window.parent as? TilingContainer, parent.layout == .dwindle else {
                    return io.err("Automatic orientation requires dwindle layout")
                }
                parent.dwindleOrientation = nil
                return true
            case .horizontal:
                return changeTilingLayout(io, targetLayout: nil, targetOrientation: .h, window: window)
            case .vertical:
                return changeTilingLayout(io, targetLayout: nil, targetOrientation: .v, window: window)
            case .tiling:
                guard let parent = window.parent else { return false }
                switch parent.cases {
                    case .macosPopupWindowsContainer:
                        return false // Impossible
                    case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
                        return io.err("Can't change layout for macOS minimized, fullscreen windows or windows or hidden apps. This behavior is subject to change")
                    case .tilingContainer:
                        return true // Nothing to do
                    case .workspace(let workspace):
                        window.lastFloatingSize = try await window.getAxSize() ?? window.lastFloatingSize
                        try await window.relayoutWindow(on: workspace, forceTile: true)
                        return true
                }
            case .floating:
                let workspace = target.workspace
                window.bindAsFloatingWindow(to: workspace)
                if let size = window.lastFloatingSize { window.setAxFrame(nil, size) }
                return true
        }
    }
}

@MainActor var layoutForNextDetectedWindow: LayoutCmdArgs.LayoutDescription?

@MainActor private func changeTilingLayout(_ io: CmdIo, targetLayout: Layout?, targetOrientation: Orientation?, window: Window) -> Bool {
    guard let parent = window.parent else { return false }
    switch parent.cases {
        case .tilingContainer(let immediateParent):
            let parent = immediateParent
            let requestedOrientation = targetOrientation
            let targetOrientation = targetOrientation ?? parent.orientation
            let targetLayout = targetLayout ?? parent.layout
            if targetLayout == .dwindle, let requestedOrientation {
                parent.dwindleOrientation = requestedOrientation
            }
            parent.layout = targetLayout
            parent.changeOrientation(targetOrientation)
            return true
        case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return io.err("The window is non-tiling")
    }
}

extension Window {
    @MainActor fileprivate func matchesDescription(_ layout: LayoutCmdArgs.LayoutDescription) -> Bool {
        let layoutParent = parent as? TilingContainer
        return switch layout {
            case .stacked: layoutParent?.layout == .stacked
            case .tabGroup:   layoutParent?.layout == .tabGroup
            case .tiles:       layoutParent?.layout == .tiles
            case .auto: layoutParent.map { $0.layout == .dwindle && $0.dwindleOrientation == nil } == true
            case .horizontal: layoutParent.map { ($0.layout == .dwindle ? $0.dwindleOrientation : $0.orientation) == .h } == true
            case .vertical: layoutParent.map { ($0.layout == .dwindle ? $0.dwindleOrientation : $0.orientation) == .v } == true
            case .hTabGroup:   layoutParent.map { $0.layout == .tabGroup && $0.orientation == .h } == true
            case .vTabGroup:   layoutParent.map { $0.layout == .tabGroup && $0.orientation == .v } == true
            case .h_tiles:     layoutParent.map { $0.layout == .tiles && $0.orientation == .h } == true
            case .v_tiles:     layoutParent.map { $0.layout == .tiles && $0.orientation == .v } == true
            case .tiling:      parent is TilingContainer
            case .floating:    parent is Workspace
        }
    }
}
