import SwiftUI

struct WindowTabGroupFrameView: View {
    @SidebarColors var colors
    let strip: WindowTabStripViewModel
    let groupSize: CGSize

    var body: some View {
        let tabHeight = min(strip.railHeight > 0 ? strip.railHeight : strip.frame.height, groupSize.height)
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
                .stroke(colors.foreground.opacity(GlassToken.borderOpacity), lineWidth: windowTabGroupFrameStrokeWidth)
                .glassShadow(.raised)

            Rectangle()
                .fill(colors.separator)
                .frame(height: StrokeToken.hairline)
                .offset(y: tabHeight - StrokeToken.hairline)
            // No line along the inner boundary: the window draws its own edge there, and a second
            // stroke doubled it into two concentric lines at the corners.

            if !strip.isExpanded {
                WindowTabPillRail(tabs: strip.tabs, shownWindowIds: strip.shownWindowIds)
                    .frame(width: groupSize.width, height: tabHeight)
            }
        }
        .frame(width: groupSize.width, height: groupSize.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func groupSurface<S: Shape>(in shape: S) -> some View {
        OverlaySurface()
            .clipShape(shape)
    }
}
