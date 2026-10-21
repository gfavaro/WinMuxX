import SwiftUI

struct WindowTabItemView: View {
    @SidebarColors var colors

    let tab: WindowTabItemViewModel
    let width: CGFloat
    let height: CGFloat
    let isDragSource: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 6) {
            appIcon(size: 14)

            Text(tab.title)
                .font(.system(size: 12, weight: tab.isActive ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(tabForegroundStyle)
        .padding(.horizontal, 10)
        .frame(width: width, height: height, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(colors.foreground.opacity(tab.isActive ? GlassToken.fillActive : isHovered ? GlassToken.fillHover : GlassToken.fillFaint))
        }
        .overlay {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .stroke(tabStrokeStyle, lineWidth: colors.increasedContrast ? StrokeToken.emphasis : StrokeToken.control)
        }
        .opacity(isDragSource ? 0.55 : 1.0)
        .contentShape(Rectangle())
    }

    private var tabForegroundStyle: Color {
        if tab.isActive { return colors.text(opacity: GlassToken.textPrimary) }
        if isDragSource { return colors.text(opacity: GlassToken.textSecondary) }
        return colors.text(opacity: isHovered ? GlassToken.textPrimary : GlassToken.textSecondary)
    }

    private var tabStrokeStyle: Color {
        if tab.isActive { return colors.foreground.opacity(colors.increasedContrast ? 1 : GlassToken.strokeActive) }
        return colors.foreground.opacity(colors.increasedContrast ? 0.6 : isHovered ? GlassToken.strokeHover : GlassToken.strokeResting)
    }
}
