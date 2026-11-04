import SwiftUI

/// One pill per tab along the group's top edge: the active window's is longest and uses the
/// accent colour, other windows on screen (a strip's columns) are lighter, hidden ones faint.
/// Resting the pointer on the rail opens the full strip.
struct WindowTabPillRail: View {
    @SidebarColors var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tabs: [WindowTabItemViewModel]
    let shownWindowIds: Set<UInt32>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Capsule()
                    .fill(fill(for: tab))
                    .frame(width: width(for: tab), height: 4)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : windowTabPillAnimation, value: tabs.map(\.isActive))
        .animation(reduceMotion ? nil : windowTabPillAnimation, value: shownWindowIds)
        .accessibilityHidden(true)
    }

    private func width(for tab: WindowTabItemViewModel) -> CGFloat {
        tab.isActive ? 20 : shownWindowIds.contains(tab.windowId) ? 12 : 8
    }

    private func fill(for tab: WindowTabItemViewModel) -> Color {
        if tab.isActive { return .accentColor }
        return colors.foreground.opacity(shownWindowIds.contains(tab.windowId) ? 0.55 : 0.28)
    }
}
