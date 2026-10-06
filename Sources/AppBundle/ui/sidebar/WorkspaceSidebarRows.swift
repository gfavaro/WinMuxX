import AppKit
import Common
import SwiftUI

// MARK: - Window Row

struct WorkspaceSidebarWindowRow: View {
    @SidebarColors var sidebarColors: WorkspaceSidebarPalette
    enum Style {
        case window
        case tabGroupHeader
        case tabGroupChild
    }

    let title: String
    let badge: String?
    let isFocused: Bool
    let suppressFocusedStyle: Bool
    let rowHeight: CGFloat
    let isHovered: Bool
    let style: Style
    let appBundleIds: [String?]
    let appBundlePaths: [String?]

    private var isTabGroupHeader: Bool { style == .tabGroupHeader }
    private var isTabGroupChild: Bool { style == .tabGroupChild }
    private var isActiveRow: Bool { isFocused && !suppressFocusedStyle }
    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: workspaceSidebarAppIconTextSpacing) {
            appIconStack
            WorkspaceSidebarLabel(text: title, size: isTabGroupHeader ? 13 : 12.5,
                weight: isActiveRow ? .semibold : .regular, secondary: !isActiveRow, customColor: rowTextColor)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isTabGroupHeader ? sidebarColors.text(opacity: 0.50) : sidebarColors.text(opacity: 0.38))
            }
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, 1)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowShape
                .fill(rowBackgroundFill)
            if isHovered {
                rowShape
                    .fill(rowHoverOverlayFill)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var appIconStack: some View {
        if isTabGroupHeader {
            HStack(spacing: -3) {
                ForEach(Array(appIconInputs.prefix(4).enumerated()), id: \.offset) { _, input in
                    appIcon(input)
                }
            }
        } else if let input = appIconInputs.first {
            appIcon(input)
        }
    }

    private var appIconInputs: [(String?, String?)] {
        Array(zip(appBundleIds, appBundlePaths)).filter { $0.0 != nil || $0.1 != nil }
    }

    private func appIcon(_ input: (String?, String?)) -> some View {
        Group {
            if let icon = appIconImage(bundleIdentifier: input.0, bundlePath: input.1) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: workspaceSidebarAppIconSize, height: workspaceSidebarAppIconSize)
                    .cornerRadius(3)
                    .opacity(rowIconOpacity)
            }
        }
    }

    private var rowTextColor: Color {
        if isActiveRow {
            return sidebarColors.text(opacity: isTabGroupHeader ? 0.96 : 1)
        }
        if isTabGroupChild {
            return sidebarColors.text(opacity: 0.58)
        }
        return sidebarColors.text(opacity: 0.78)
    }

    private var rowIconOpacity: Double {
        isTabGroupChild ? 0.56 : 1
    }

    private var rowBackgroundFill: Color {
        if isActiveRow {
            if isTabGroupHeader {
                return sidebarColors.foreground.opacity(0.14)
            }
            if isTabGroupChild {
                return sidebarColors.foreground.opacity(0.055)
            }
            return sidebarColors.foreground.opacity(0.085)
        }
        return Color.clear
    }

    private var rowHoverOverlayFill: Color {
        if isTabGroupHeader {
            return sidebarColors.foreground.opacity(0.04)
        }
        if isTabGroupChild {
            return sidebarColors.foreground.opacity(0.03)
        }
        return sidebarColors.foreground.opacity(0.045)
    }
}
