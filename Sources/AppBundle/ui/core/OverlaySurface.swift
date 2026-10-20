import AppKit
import SwiftUI

/// Palette and overview use the expanded sidebar's chrome and accessibility colors.
struct OverlaySurface: View {
    var cornerRadius: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarPreviewAccessibility) private var previewAccessibility

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if config.workspaceSidebar.effectiveAppearance == .custom {
                GlassSurface(shape: shape, hasBorder: false,
                    style: config.workspaceSidebar.chromeStyle,
                    solidColor: config.workspaceSidebar.resolvedSolidChromeColor)
            } else if reduceTransparency || previewAccessibility.reduceTransparency {
                shape.fill(Color(nsColor: workspaceSidebarOpaqueColor(dark: colorScheme == .dark)))
            } else {
                ZStack {
                    WorkspaceSidebarGlassSurface()
                    if config.workspaceSidebar.frostedTint != .automatic {
                        WorkspaceSidebarFrostedVeil(tint: config.workspaceSidebar.frostedTint)
                    }
                }
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

@MainActor
func overlayAppearanceSnapshot(monitor: MonitorViewportId? = nil) -> WorkspaceSidebarSnapshot {
    var snapshot = workspaceSidebarSnapshot(from: TrayMenuModel.shared)
    snapshot.configuration = workspaceSidebarConfiguration()
    snapshot.configuration.alwaysExpanded = true
    snapshot.visibleWidth = snapshot.configuration.expandedWidth
    snapshot.targetMonitorScopeId = monitor.flatMap { id in
        sortedMonitors.first { MonitorViewportId($0) == id }.map(workspaceSidebarMonitorScopeId)
    } ?? TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId
    return snapshot
}

struct OverlayAppearance: ViewModifier {
    var monitor: MonitorViewportId? = nil
    @ObservedObject private var tray = TrayMenuModel.shared

    func body(content: Content) -> some View {
        content.modifier(OverlayResolvedAppearance())
            .modifier(WorkspaceSidebarWallpaperContrast(snapshot: overlayAppearanceSnapshot(monitor: monitor),
                refreshGeneration: tray.workspaceSidebarWallpaperRefreshGeneration))
    }
}

private struct OverlayResolvedAppearance: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let sidebar = config.workspaceSidebar
        let scheme = sidebar.effectiveAppearance == .custom
            ? workspaceSidebarSolidColorScheme(sidebar.resolvedSolidChromeColor)
            : sidebar.frostedTint.preferredColorScheme ?? colorScheme
        content.environment(\.colorScheme, scheme)
            .environment(\.workspaceSidebarAppearance, sidebar.effectiveAppearance)
    }
}

@MainActor
func overlayHasMarkedText(_ responder: NSResponder?) -> Bool {
    (responder as? any NSTextInputClient)?.hasMarkedText() ?? false
}
