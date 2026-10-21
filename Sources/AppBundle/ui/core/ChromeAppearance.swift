import AppKit
import SwiftUI

struct ChromeAppearanceInputs {
    var theme: AppAppearance = .system
    var appearance: WorkspaceSidebarAppearance = .system
    var solidColor: Color = .black
    var tint: WorkspaceSidebarFrostedTint = .automatic
    var systemScheme: ColorScheme = .light
    var reduceTransparency = false
    var increasedContrast = false
}

struct ResolvedChromeAppearance: Equatable {
    enum Material: Equatable { case glass, opaque, solid }
    let material: Material
    let scheme: ColorScheme
    let fill: Color?
    let veil: WorkspaceSidebarFrostedTint?
    let separatorWidth: CGFloat
}

func resolveChromeAppearance(inputs: ChromeAppearanceInputs) -> ResolvedChromeAppearance {
    let custom = inputs.appearance == .custom
    // Theme is independent of wallpaper and decorative tint. Custom solid colors
    // retain a contrasting foreground even when the selected theme differs.
    let scheme = custom ? workspaceSidebarSolidColorScheme(inputs.solidColor)
        : inputs.theme.colorScheme(system: inputs.systemScheme)
    return ResolvedChromeAppearance(material: custom ? .solid : inputs.reduceTransparency ? .opaque : .glass,
        scheme: scheme,
        fill: custom ? inputs.solidColor : inputs.reduceTransparency
            ? Color(nsColor: workspaceSidebarOpaqueColor(dark: scheme == .dark)) : nil,
        veil: !custom && !inputs.reduceTransparency && inputs.tint != .automatic ? inputs.tint : nil,
        separatorWidth: inputs.increasedContrast ? 2 : 0.5)
}

extension WorkspaceSidebarConfiguration {
    func chromeAppearance(systemScheme: ColorScheme,
                          reduceTransparency: Bool, increasedContrast: Bool = false) -> ResolvedChromeAppearance {
        resolveChromeAppearance(inputs: ChromeAppearanceInputs(theme: theme, appearance: appearance,
            solidColor: resolvedSolidChromeColor, tint: frostedTint, systemScheme: systemScheme,
            reduceTransparency: reduceTransparency, increasedContrast: increasedContrast))
    }
}

extension AppAppearance {
    func colorScheme(system: ColorScheme) -> ColorScheme {
        switch self {
            case .system: system
            case .light: .light
            case .dark: .dark
        }
    }
}
