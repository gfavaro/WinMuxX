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

struct WorkspaceSidebarDropdownMenuRowStyle: ViewModifier {
    @SidebarColors var sidebarColors: WorkspaceSidebarPalette
    let isSelected: Bool
    var rowHeight: CGFloat = workspaceSidebarDropdownHeight
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, workspaceSidebarDropdownPadding)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowFill)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.10), value: isHovered)
    }

    private var rowFill: Color {
        if isSelected {
            return sidebarColors.foreground.opacity(isHovered ? 0.10 : 0.06)
        }
        return sidebarColors.foreground.opacity(isHovered ? 0.07 : 0)
    }
}

func checkmark(isVisible: Bool) -> some View {
    WorkspaceSidebarCheckmark(isVisible: isVisible)
}

private struct WorkspaceSidebarCheckmark: View {
    @SidebarColors var sidebarColors: WorkspaceSidebarPalette
    let isVisible: Bool

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(sidebarColors.text(opacity: isVisible ? 0.80 : 0))
    }
}
