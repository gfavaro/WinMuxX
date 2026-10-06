import SwiftUI

struct WindowTabGroupFrameView: View {
    let strip: WindowTabStripViewModel
    let groupSize: CGSize

    var body: some View {
        let tabHeight = min(strip.frame.height, groupSize.height)
        let outerShape = WindowTabGroupOuterShape(activeWindowCornerRadius: strip.activeWindowCornerRadius)
        let shellShape = WindowTabGroupShellShape(
            tabBarHeight: tabHeight,
            activeWindowCornerRadius: strip.activeWindowCornerRadius,
        )
        ZStack(alignment: .topLeading) {
            // The shell includes the tab bar and the visible border around the active window.
            // Its even-odd mask keeps the window body transparent while retaining that chrome.
            groupSurface(in: outerShape)
                .mask {
                    shellShape.fill(style: FillStyle(eoFill: true))
                }

            outerShape
                .stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: windowTabGroupFrameStrokeWidth)
                .glassShadow(.raised)

            Rectangle()
                .fill(Color.white.opacity(GlassToken.separatorOpacity))
                .frame(height: StrokeToken.hairline)
                .offset(y: tabHeight - StrokeToken.hairline)

            WindowTabGroupInnerBoundaryShape(
                tabBarHeight: tabHeight,
                activeWindowCornerRadius: strip.activeWindowCornerRadius,
            )
            .stroke(mattePanelInsetShadow, lineWidth: windowTabGroupFrameInnerStrokeWidth)
        }
        .frame(width: groupSize.width, height: groupSize.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func groupSurface<S: Shape>(in shape: S) -> some View {
        if config.workspaceSidebar.chromeStyle == .solid {
            GlassSurface(shape: shape, style: .solid,
                solidColor: config.workspaceSidebar.resolvedSolidChromeColor)
        } else {
            WorkspaceSidebarFrostedSurface(tint: config.workspaceSidebar.frostedTint)
                .clipShape(shape)
                .environment(\.colorScheme, config.workspaceSidebar.frostedTint.preferredColorScheme ?? colorScheme)
        }
    }

    @Environment(\.colorScheme) private var colorScheme

}
