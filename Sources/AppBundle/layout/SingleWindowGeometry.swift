import AppKit
import Common

func windowWidthRect(available: Rect, fraction: Double, minimumWidth: CGFloat) -> Rect {
    centeredSingleWindowRect(available: available, width: available.width * fraction, minimumWidth: minimumWidth)
}

@MainActor
func fullscreenWindowRect(_ window: Window, in workspace: Workspace) -> Rect {
    let monitor = workspace.workspaceMonitor
    let available = window.noOuterGapsInFullscreen ? monitor.visibleRect : monitor.visibleRectPaddedByOuterGaps
    guard let fraction = workspace.windowWidthSettings.fullscreenWidth else { return available }
    return windowWidthRect(available: available, fraction: fraction, minimumWidth: window.minimumLayoutSize.width)
}

func singleWindowLimitedRect(available: Rect, screen: Rect, ratio: Double, minimumWidth: CGFloat) -> Rect {
    guard ratio.isFinite, ratio > 0, screen.height > 0, screen.width / screen.height >= 2.3 else { return available }
    let width = min(available.width, max(max(available.height - 1, 0) * CGFloat(ratio), minimumWidth))
    return centeredSingleWindowRect(available: available, width: width, minimumWidth: minimumWidth)
}

@MainActor
func singleWindowWidthTarget(in workspace: Workspace) -> Window? {
    let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
    guard windows.count == 1, let window = windows.first, !window.isFullscreen else { return nil }
    if workspace.windowWidthSettings.fullscreenWidth != nil { return window }
    // Compatibility for configs written before fullscreen-width.
    guard workspace.arrangement != .master else { return nil }
    let monitor = workspace.workspaceMonitor
    let ratio = config.singleWindowAspectRatio.getValue(for: monitor)
    guard ratio.isFinite, ratio > 0, monitor.rect.height > 0,
          monitor.rect.width / monitor.rect.height >= 2.3 else { return nil }
    guard !window.parents.contains(where: { ($0 as? TilingContainer).map { $0.layout == .tabGroup || $0.layout == .stacked } == true }) else { return nil }
    return window
}

@MainActor
func workspaceTilingRect(_ workspace: Workspace) -> Rect {
    let monitor = workspace.workspaceMonitor
    let available = monitor.visibleRectPaddedByOuterGaps
    let settings = workspace.windowWidthSettings
    if let fraction = settings.fullscreenWidth {
        let root = workspace.rootTilingContainer
        if let group = root.allTabbedContainersRecursive.first(where: \.hasFullscreenTab) {
            let minimum = group.allLeafWindowsRecursive.map { $0.minimumLayoutSize.width }.max() ?? 0
            return windowWidthRect(available: available, fraction: fraction, minimumWidth: minimum)
        }
        if let window = root.mostRecentWindowRecursive, window.isFullscreen {
            return fullscreenWindowRect(window, in: workspace)
        }
    }
    guard let window = singleWindowWidthTarget(in: workspace) else { return available }
    if let width = window.singleWindowManualWidth {
        return centeredSingleWindowRect(available: available, width: width, minimumWidth: window.minimumLayoutSize.width)
    }
    if let fraction = settings.fullscreenWidth {
        return windowWidthRect(available: available, fraction: fraction, minimumWidth: window.minimumLayoutSize.width)
    }
    return singleWindowLimitedRect(available: available, screen: monitor.rect,
        ratio: config.singleWindowAspectRatio.getValue(for: monitor), minimumWidth: window.minimumLayoutSize.width)
}

func centeredSingleWindowRect(available: Rect, width: CGFloat, minimumWidth: CGFloat) -> Rect {
    guard width.isFinite, width > 0 else { return available }
    let fittedWidth = min(available.width, max(width, minimumWidth))
    return Rect(topLeftX: available.topLeftX + (available.width - fittedWidth) / 2,
        topLeftY: available.topLeftY, width: fittedWidth, height: available.height)
}

@MainActor
@discardableResult
func applySingleWindowManualResize(_ window: Window, width: CGFloat) -> Bool {
    guard width.isFinite, width > 0, let workspace = window.nodeWorkspace,
          singleWindowWidthTarget(in: workspace) === window else { return false }
    window.singleWindowManualWidth = width
    return true
}

/// A height-changing user gesture leaves the constrained lone-tile layout.
/// Compare the physical frame (including the existing one-point height adjustment)
/// and tolerate small AX rounding differences.
@MainActor
@discardableResult
func floatSingleWindowAfterHeightResize(_ window: Window, rect: Rect) -> Bool {
    guard rect.width.isFinite, rect.height.isFinite, rect.topLeftX.isFinite, rect.topLeftY.isFinite,
          rect.width > 0, rect.height > 0,
          let workspace = window.nodeWorkspace,
          singleWindowWidthTarget(in: workspace) === window,
          let previous = window.lastAppliedLayoutPhysicalRect,
          abs(rect.height - previous.height) > 5 else { return false }
    window.singleWindowManualWidth = rect.width
    window.lastFloatingSize = rect.size
    window.bindAsFloatingWindow(to: workspace)
    window.lastAppliedLayoutPhysicalRect = nil
    window.lastAppliedLayoutVirtualRect = nil
    window.setAxFrame(rect.topLeftCorner, rect.size)
    window.recordAuthoritativeActualRect(rect)
    return true
}
