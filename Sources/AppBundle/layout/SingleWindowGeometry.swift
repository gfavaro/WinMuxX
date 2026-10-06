import AppKit
import Common

func singleWindowLimitedRect(available: Rect, screen: Rect, ratio: Double, minimumWidth: CGFloat, alignment: SingleWindowAlignment = .center) -> Rect {
    guard ratio.isFinite, ratio > 0, screen.height > 0, screen.width / screen.height >= 2.3 else { return available }
    let width = min(available.width, max(max(available.height - 1, 0) * CGFloat(ratio), minimumWidth))
    return alignedSingleWindowRect(available: available, width: width, minimumWidth: minimumWidth, alignment: alignment)
}

@MainActor
func singleWindowAspectRatioTarget(in workspace: Workspace) -> Window? {
    let monitor = workspace.workspaceMonitor
    let ratio = config.singleWindowAspectRatio.getValue(for: monitor)
    guard ratio.isFinite, ratio > 0, monitor.rect.height > 0,
          monitor.rect.width / monitor.rect.height >= 2.3 else { return nil }
    let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
    guard windows.count == 1, workspace.floatingWindows.isEmpty,
          let window = windows.first, !window.isFullscreen,
          !window.parents.contains(where: { ($0 as? TilingContainer)?.layout == .tabGroup }) else { return nil }
    return window
}

@MainActor
func workspaceTilingRect(_ workspace: Workspace) -> Rect {
    let monitor = workspace.workspaceMonitor
    let available = monitor.visibleRectPaddedByOuterGaps
    guard let window = singleWindowAspectRatioTarget(in: workspace) else { return available }
    if let width = window.singleWindowManualWidth {
        return alignedSingleWindowRect(available: available, width: width, minimumWidth: window.minimumLayoutSize.width, alignment: config.singleWindowAlignment)
    }
    return singleWindowLimitedRect(available: available, screen: monitor.rect,
        ratio: config.singleWindowAspectRatio.getValue(for: monitor), minimumWidth: window.minimumLayoutSize.width, alignment: config.singleWindowAlignment)
}

func alignedSingleWindowRect(available: Rect, width: CGFloat, minimumWidth: CGFloat, alignment: SingleWindowAlignment = .center) -> Rect {
    guard width.isFinite, width > 0 else { return available }
    let fittedWidth = min(available.width, max(width, minimumWidth))
    let inset: CGFloat = switch alignment {
        case .left: 0
        case .center: (available.width - fittedWidth) / 2
        case .right: available.width - fittedWidth
    }
    return Rect(topLeftX: available.topLeftX + inset,
        topLeftY: available.topLeftY, width: fittedWidth, height: available.height)
}

@MainActor
@discardableResult
func applySingleWindowManualResize(_ window: Window, width: CGFloat) -> Bool {
    guard width.isFinite, width > 0, let workspace = window.nodeWorkspace,
          singleWindowAspectRatioTarget(in: workspace) === window else { return false }
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
          singleWindowAspectRatioTarget(in: workspace) === window,
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
