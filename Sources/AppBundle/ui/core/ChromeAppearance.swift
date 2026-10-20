import AppKit
import SwiftUI

struct ChromeAppearanceInputs {
    var appearance: WorkspaceSidebarAppearance = .system
    var solidColor: Color = .black
    var tint: WorkspaceSidebarFrostedTint = .automatic
    var systemScheme: ColorScheme = .light
    var menuBarScheme: ColorScheme?
    var wallpaperTone: WorkspaceSidebarWallpaperTone?
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
    let scheme = custom ? workspaceSidebarSolidColorScheme(inputs.solidColor)
        : inputs.tint.preferredColorScheme ?? (inputs.reduceTransparency ? inputs.systemScheme
            : workspaceSidebarResolvedColorScheme(menuBarColorScheme: inputs.menuBarScheme,
                wallpaperTone: inputs.wallpaperTone, systemColorScheme: inputs.systemScheme))
    return ResolvedChromeAppearance(material: custom ? .solid : inputs.reduceTransparency ? .opaque : .glass,
        scheme: scheme,
        fill: custom ? inputs.solidColor : inputs.reduceTransparency
            ? Color(nsColor: workspaceSidebarOpaqueColor(dark: scheme == .dark)) : nil,
        veil: !custom && !inputs.reduceTransparency && inputs.tint != .automatic ? inputs.tint : nil,
        separatorWidth: inputs.increasedContrast ? 2 : 0.5)
}

extension WorkspaceSidebarConfiguration {
    func chromeAppearance(systemScheme: ColorScheme, wallpaperTone: WorkspaceSidebarWallpaperTone? = nil,
                          reduceTransparency: Bool, increasedContrast: Bool = false) -> ResolvedChromeAppearance {
        resolveChromeAppearance(inputs: ChromeAppearanceInputs(appearance: appearance,
            solidColor: resolvedSolidChromeColor, tint: frostedTint, systemScheme: systemScheme,
            wallpaperTone: wallpaperTone, reduceTransparency: reduceTransparency, increasedContrast: increasedContrast))
    }
}
