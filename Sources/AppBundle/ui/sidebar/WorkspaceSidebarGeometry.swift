import AppKit

/// All modes retain the menu-bar reveal area, including when macOS auto-hides it.
func workspaceSidebarPanelFrame(
    screen: CGRect,
    menuBarHeight: CGFloat,
    config: WorkspaceSidebarConfig,
    contentHeight: CGFloat
) -> CGRect {
    let reserve = min(max(0, menuBarHeight, config.heightMode == nil ? CGFloat(config.menuBarReserveHeight) : 0), max(0, screen.height - 1))
    let availableHeight = max(1, screen.height - reserve)
    let height = config.heightMode == .centered
        ? min(max(1, contentHeight), availableHeight * 0.9)
        : availableHeight
    let width = CGFloat(config.width) * 2
    return CGRect(
        x: config.position == .left ? screen.minX : screen.maxX - width,
        y: screen.minY + (availableHeight - height) / 2,
        width: width,
        height: height
    )
}

func workspaceSidebarVisibleFrame(panel: CGRect, width: CGFloat, position: WorkspaceSidebarPosition) -> CGRect {
    let width = max(0, min(width, panel.width))
    return CGRect(x: position == .left ? panel.minX : panel.maxX - width, y: panel.minY, width: width, height: panel.height)
}

struct WorkspaceSidebarPanelLayout {
    let frame: NSRect
    let expandedWidth: CGFloat
    let collapsedWidth: CGFloat
}

extension WorkspaceSidebarPanel {
    func currentSidebarPanelLayout() -> WorkspaceSidebarPanelLayout? {
        currentSidebarPanelLayout(on: workspaceSidebarResolvedPanelMonitor())
    }

    func currentSidebarPanelLayout(on monitor: Monitor) -> WorkspaceSidebarPanelLayout? {
        guard TrayMenuModel.shared.isEnabled,
              config.workspaceSidebar.enabled,
              let screen = workspaceSidebarPanelScreen(for: monitor)
        else { return nil }
        guard !shouldSuppressWorkspaceSidebarForFullscreenContent() else { return nil }

        let sidebarConfig = config.workspaceSidebar
        let expandedWidth = CGFloat(sidebarConfig.width)
        let collapsedWidth = workspaceSidebarRestingWidth(sidebarConfig)
        guard expandedWidth > 0, collapsedWidth >= 0 else { return nil }

        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        return WorkspaceSidebarPanelLayout(
            frame: workspaceSidebarPanelFrame(screen: screen.frame, menuBarHeight: menuBarHeight, config: sidebarConfig, contentHeight: measuredContentHeight > 0 ? measuredContentHeight : screen.frame.height * 0.6),
            expandedWidth: expandedWidth,
            collapsedWidth: collapsedWidth,
        )
    }

    func workspaceSidebarPanelScreen() -> NSScreen? {
        workspaceSidebarPanelScreen(for: workspaceSidebarResolvedPanelMonitor())
    }

    func workspaceSidebarPanelScreen(for monitor: Monitor) -> NSScreen? {
        NSScreen.screens.getOrNil(
            atIndex: monitor.monitorAppKitNsScreenScreensId - 1
        ) ?? NSScreen.screens.first
    }
}
