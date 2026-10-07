import SwiftUI

struct WorkspaceSidebarDropdownControlStyle: ViewModifier {
    @SidebarColors var sidebarColors: WorkspaceSidebarPalette
    let isActive: Bool
    var activeFill: Color? = nil
    var activeStroke: Color? = nil
    var inactiveFill: Color? = nil
    var inactiveHoverFill: Color? = nil
    var inactiveStroke: Color? = nil
    var inactiveHoverStroke: Color? = nil
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, workspaceSidebarDropdownPadding)
            .frame(height: workspaceSidebarDropdownHeight)
            .background {
                RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                    .fill(controlFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                            .strokeBorder(controlStroke, lineWidth: isHovered || isActive ? 0.65 : 0.5)
                    }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var controlFill: Color {
        if isActive {
            return activeFill ?? sidebarColors.foreground.opacity(0.12)
        }
        return isHovered
            ? inactiveHoverFill ?? sidebarColors.foreground.opacity(0.10)
            : inactiveFill ?? sidebarColors.foreground.opacity(0.06)
    }

    private var controlStroke: Color {
        if isActive {
            return activeStroke ?? sidebarColors.foreground.opacity(0.18)
        }
        return isHovered
            ? inactiveHoverStroke ?? (sidebarColors.appearance == .system ? sidebarColors.separator : .white.opacity(0.14))
            : inactiveStroke ?? sidebarColors.foreground.opacity(0.08)
    }
}
