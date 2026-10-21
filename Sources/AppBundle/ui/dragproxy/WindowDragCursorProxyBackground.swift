import SwiftUI

struct WindowDragCursorProxyBackground: View {
    var isGroup: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
            .fill(Color.primary.opacity(isGroup ? GlassToken.fillActive : GlassToken.fillHover))
            .overlay {
                RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(GlassToken.strokeHover), lineWidth: StrokeToken.control)
            }
            .background(OverlaySurface(cornerRadius: workspaceSidebarRowCornerRadius))
            .glassShadow(.resting)
    }
}
