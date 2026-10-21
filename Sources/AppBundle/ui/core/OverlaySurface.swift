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
        let appearance = workspaceSidebarConfiguration().chromeAppearance(systemScheme: colorScheme,
            reduceTransparency: reduceTransparency || previewAccessibility.reduceTransparency)
        Group {
            if let fill = appearance.fill { shape.fill(fill) }
            else {
                ZStack {
                    WorkspaceSidebarGlassSurface()
                    if let tint = appearance.veil { WorkspaceSidebarFrostedVeil(tint: tint) }
                }
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

struct OverlayAppearance: ViewModifier {
    var monitor: MonitorViewportId? = nil
    @ObservedObject private var tray = TrayMenuModel.shared

    func body(content: Content) -> some View {
        let configuration = workspaceSidebarConfiguration()
        let scope = monitor.flatMap { id in
            sortedMonitors.first { MonitorViewportId($0) == id }.map(workspaceSidebarMonitorScopeId)
        } ?? tray.workspaceSidebarFocusedMonitorScopeId
        content.modifier(ChromeResolvedAppearance())
            .modifier(WorkspaceSidebarWallpaperContrast(configuration: configuration, visibleWidth: configuration.expandedWidth, targetMonitorScopeId: scope,
                refreshGeneration: tray.workspaceSidebarWallpaperRefreshGeneration))
    }
}

struct ChromeResolvedAppearance: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.workspaceSidebarPreviewAccessibility) private var previewAccessibility

    func body(content: Content) -> some View {
        let configuration = workspaceSidebarConfiguration()
        let resolved = configuration.chromeAppearance(systemScheme: colorScheme,
            reduceTransparency: reduceTransparency || previewAccessibility.reduceTransparency)
        content.environment(\.colorScheme, resolved.scheme)
            .environment(\.workspaceSidebarAppearance, configuration.appearance)
    }
}

@MainActor
func overlayHasMarkedText(_ responder: NSResponder?) -> Bool {
    (responder as? any NSTextInputClient)?.hasMarkedText() ?? false
}
