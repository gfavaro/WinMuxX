import AppKit
import Common

struct ListWindowsCommand: Command {
    let isQuery = true
    let args: ListWindowsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let focus = focus
        var windows: [Window] = []

        if args.filteringOptions.focused {
            if let window = focus.windowOrNil {
                windows = [window]
            } else {
                return io.err(noWindowIsFocused)
            }
        } else {
            let allWorkspaces = runtime.workspaceBackend.kind == .native
                ? nativeDesktopWorkspaces().map(\.workspace)
                : userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
            var workspaces: Set<Workspace> = args.filteringOptions.workspaces.isEmpty
                ? allWorkspaces.toSet()
                : args.filteringOptions.workspaces
                    .flatMap { filter in
                        switch filter {
                            case .focused: [focus.workspace]
                            case .visible: Workspace.all.filter(\.isVisible)
                            case .name(let name): userWorkspace(named: name.raw).map { [$0] } ?? []
                        }
                    }
                    .toSet()
            if !args.filteringOptions.monitors.isEmpty {
                let monitors: Set<CGPoint> = args.filteringOptions.monitors.resolveMonitors(io)
                if monitors.isEmpty { return false }
                workspaces = workspaces.filter { monitors.contains($0.workspaceMonitor.rect.topLeftCorner) }
            }
            windows = workspaces.flatMap(\.allLeafWindowsRecursive)
            if let pid = args.filteringOptions.pidFilter {
                windows = windows.filter { $0.app.pid == pid }
            }
            if let appId = args.filteringOptions.appIdFilter {
                windows = windows.filter { $0.app.rawAppBundleId == appId }
            }
        }

        if args.outputOnlyCount {
            return io.out("\(windows.count)")
        }
        let needsTitle = args.format.contains { token in
            if case .interVar(FormatVar.WindowFormatVar.windowTitle.rawValue) = token { return true }
            return false
        }
        var windowInfos: [(window: Window, title: String)] = []
        for window in windows {
            windowInfos.append((window, needsTitle ? try await window.title : ""))
        }
        windowInfos = windowInfos
            .filter { $0.window.isBound }
            .sorted { lhs, rhs in
                let lhsApp = lhs.window.app.name ?? ""
                let rhsApp = rhs.window.app.name ?? ""
                if lhsApp != rhsApp { return lhsApp < rhsApp }
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.window.windowId < rhs.window.windowId
            }

        return windowInfos.map { FormatObject.window(window: $0.window, title: $0.title) }.writeFormattedOutput(
            to: io,
            format: args.format,
            json: args.json,
            ignoreRightPaddingVar: args._format.isEmpty,
        )
    }
}
