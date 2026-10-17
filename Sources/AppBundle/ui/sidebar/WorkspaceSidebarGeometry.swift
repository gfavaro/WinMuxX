import AppKit

/// All modes retain the menu-bar reveal area, including when macOS auto-hides it.
func workspaceSidebarPanelFrame(
    screen: CGRect,
    menuBarHeight: CGFloat,
    config: WorkspaceSidebarConfig,
    contentHeight: CGFloat,
    backingWidth: CGFloat? = nil
) -> CGRect {
    let reserve = min(max(0, menuBarHeight, config.heightMode == nil ? CGFloat(config.menuBarReserveHeight) : 0), max(0, screen.height - 1))
    let availableHeight = max(1, screen.height - reserve)
    let height = config.heightMode == .centered
        ? min(max(1, contentHeight), availableHeight * 0.9)
        : availableHeight
    let width = max(1, backingWidth ?? CGFloat(config.width) * 2)
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

        let menuBarHeight = WorkspaceSidebarMenuBarGeometry.height(on: screen)
        return WorkspaceSidebarPanelLayout(
            frame: workspaceSidebarPanelFrame(screen: screen.frame, menuBarHeight: menuBarHeight, config: sidebarConfig, contentHeight: measuredContentHeight > 0 ? measuredContentHeight : screen.frame.height * 0.6,
                backingWidth: workspaceSidebarBackingWidth(
                    config: sidebarConfig,
                    visibleWidth: viewModel.workspaceSidebarVisibleWidth,
                    isExpanded: viewModel.isWorkspaceSidebarExpanded,
                    isAnimating: pendingBackingResize != nil
                )
            ),
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

/// visibleFrame includes system clearance below the menu bar. Prefer the rendered
/// menu's bounds on this display so that clearance does not become a wallpaper seam.
func workspaceSidebarRenderedMenuBarHeight(screen: CGRect, safeAreaTop: CGFloat,
                                           fallback: CGFloat, menuBars: [CGRect]) -> CGFloat {
    menuBars.first {
        abs($0.minX - screen.minX) <= 1 && abs($0.minY - screen.minY) <= 1 &&
            abs($0.width - screen.width) <= 1 && $0.height >= safeAreaTop &&
            $0.height > 0 && $0.height < screen.height
    }?.height ?? fallback
}

@MainActor
private enum WorkspaceSidebarMenuBarGeometry {
    private struct Signature: Equatable {
        let frame: CGRect
        let visibleFrame: CGRect
        let safeAreaTop: CGFloat
        let statusBarHeight: CGFloat
    }
    private static var cache: [UInt32: (Signature, CGFloat)] = [:]

    static func height(on screen: NSScreen) -> CGFloat {
        let signature = Signature(frame: screen.frame, visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top, statusBarHeight: NSStatusBar.system.thickness)
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        if let id, let cached = cache[id], cached.0 == signature { return cached.1 }
        let fallback = max(screen.frame.maxY - screen.visibleFrame.maxY,
            signature.safeAreaTop, signature.statusBarHeight)
        let mainTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let cgScreen = CGRect(x: screen.frame.minX, y: mainTop - screen.frame.maxY,
            width: screen.frame.width, height: screen.frame.height)
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let level = Int(CGWindowLevelForKey(.mainMenuWindow))
        let bars = windows.compactMap { info -> CGRect? in
            guard info[kCGWindowLayer as String] as? Int == level,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        let height = workspaceSidebarRenderedMenuBarHeight(screen: cgScreen,
            safeAreaTop: signature.safeAreaTop, fallback: fallback, menuBars: bars)
        if let id { cache[id] = (signature, height) }
        return height
    }
}

/// Keep the browsing canvas during transitions; idle rails need only their hit region.
func workspaceSidebarBackingWidth(
    config: WorkspaceSidebarConfig, visibleWidth: CGFloat, isExpanded: Bool, isAnimating: Bool
) -> CGFloat {
    if config.alwaysExpanded || isExpanded || isAnimating || visibleWidth > workspaceSidebarRestingWidth(config) + 0.5 {
        return CGFloat(config.width) * 2
    }
    return max(1, workspaceSidebarHoverActivationWidth(config), workspaceSidebarRestingWidth(config))
}
