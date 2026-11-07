import AppKit
import SwiftUI

/// A border color from Settings text: `#RRGGBB` or `#RRGGBBAA`, as `[borders]` accepts.
func settingsPreviewColor(hex: String) -> Color? {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
    let rgb = digits.count == 8 ? value >> 8 : value
    let alpha = digits.count == 8 ? Double(value & 255) / 255 : 1
    return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
        blue: Double(rgb & 255) / 255, opacity: alpha)
}

/// What the border settings look like together: a focused and an unfocused window at the real
/// width, in the chosen colors and order, with the unfocused one dimmed as configured.
struct SettingsBorderPreview: View {
    let enabled: Bool
    let width: Double
    let activeColor: String
    let inactiveColor: String
    let order: WindowBorderOrder
    let dimPercent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Border preview").font(.headline)
            HStack(spacing: 18) {
                window(focused: true)
                window(focused: false)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
            .accessibilityHidden(true)
            SettingsDescription(settingsBorderPreviewCaption(enabled: enabled, width: width, order: order, dimPercent: dimPercent))
        }
    }

    private func window(focused: Bool) -> some View {
        let radius: CGFloat = 8
        let stroke = CGFloat(enabled ? width : 0)
        let color = settingsPreviewColor(hex: focused ? activeColor : inactiveColor) ?? .clear
        let border = RoundedRectangle(cornerRadius: radius + stroke / 2).strokeBorder(color, lineWidth: stroke)
            .padding(order == .below ? -stroke : 0)
        return ZStack {
            if order == .below { border }
            RoundedRectangle(cornerRadius: radius)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) { ForEach(0..<3) { _ in Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6) } }
                        .padding(7)
                }
                .overlay(RoundedRectangle(cornerRadius: radius).fill(Color.black.opacity(focused ? 0 : Double(dimPercent) / 100)))
                .overlay(Text(focused ? "Focused" : "Other").font(.caption).foregroundStyle(.secondary))
            if order == .above { border }
        }
        .frame(width: 150, height: 92)
    }
}

func settingsBorderPreviewCaption(enabled: Bool, width: Double, order: WindowBorderOrder, dimPercent: Int) -> String {
    guard enabled, width > 0 else {
        return dimPercent > 0 ? "Borders are off. Other windows are dimmed by \(dimPercent)%." : "Borders are off."
    }
    let points = width.rounded() == width ? String(Int(width)) : String(width)
    let placement = order == .below ? "drawn behind the window, so only the outer part shows" : "drawn over the window's edge"
    let dimming = dimPercent > 0 ? " Other windows are dimmed by \(dimPercent)%." : ""
    return "\(points)-point border \(placement).\(dimming)"
}

/// A tab group as it appears at rest: pills on its top edge, the front window's longest.
struct SettingsTabGroupPreview: View {
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tab group preview").font(.headline)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)))
                    .frame(width: 200, height: 64)
                    .padding(.top, 5)
                if enabled {
                    HStack(spacing: windowTabPillSpacing) {
                        ForEach(0..<3) { index in
                            Capsule()
                                .fill(index == 0 ? Color(nsColor: .controlAccentColor) : Color(nsColor: .systemGray).opacity(0.7))
                                .frame(width: windowTabPillWidth(isActive: index == 0, isShown: false), height: windowTabPillHeight)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
            .accessibilityHidden(true)
            SettingsDescription(enabled
                ? "Three windows in one group. The long accent pill is the window in front; rest the pointer on the top edge to see the tabs and switch."
                : "Tab strips are off: a group's windows overlap with small offsets instead.")
        }
    }
}
