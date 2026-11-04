import AppKit

enum WinMuxPanelLayer: CaseIterable {
    case windowChrome
    /// Small marks drawn over a window's edge, such as a tab group's pills; they must stay
    /// visible when the window comes to the front.
    case windowIndicator
    case windowIntentPreview
    case overlay
    case dragCursorProxy
    case workspaceSidebar

    var level: NSWindow.Level {
        switch self {
            case .windowChrome:
                .normal
            case .windowIndicator:
                .floating
            case .windowIntentPreview:
                .statusBar
            case .overlay:
                .statusBar
            case .dragCursorProxy:
                NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            case .workspaceSidebar:
                NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        }
    }
}

extension NSPanelHud {
    func applyWinMuxLayer(_ layer: WinMuxPanelLayer) {
        level = layer.level
    }
}
