import Common

struct CmdEnv: ConvenienceCopyable {
    var extraEnvironment: [String: String] = [:]
    var windowId: UInt32?
    var workspaceName: String?

    static let defaultEnv: CmdEnv = .init()
    func withFocus(_ focus: LiveFocus) -> CmdEnv {
        switch focus.asLeaf {
            case .window(let wd): CmdEnv(extraEnvironment: extraEnvironment, windowId: wd.windowId)
            case .emptyWorkspace(let ws): CmdEnv(extraEnvironment: extraEnvironment, workspaceName: ws.name)
        }
    }

    var asMap: [String: String] {
        var result = extraEnvironment
        if let windowId {
            result[WINMUX_WINDOW_ID] = windowId.description
        }
        if let workspaceName {
            result[WINMUX_WORKSPACE] = workspaceName.description
        }
        return result
    }
}
