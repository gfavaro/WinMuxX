@testable import AppBundle
import AppKit
import SwiftUI
import XCTest

@MainActor
final class ChromeAppearanceTest: XCTestCase {
    func testSystemAppearanceFollowsSystemAcrossDecorativeTints() {
        for system in [ColorScheme.light, .dark] {
            for tint in WorkspaceSidebarFrostedTint.allCases {
                let result = resolveChromeAppearance(inputs: .init(tint: tint, systemScheme: system))
                XCTAssertEqual(result.scheme, system)
                XCTAssertEqual(result.material, .glass)
                XCTAssertNil(result.fill)
            }
        }
    }
    func testFallbackExplicitTintAndAccessibility() {
        XCTAssertEqual(resolveChromeAppearance(inputs: .init(systemScheme: .light)).scheme, .light)
        for tint in WorkspaceSidebarFrostedTint.allCases {
            let glass = resolveChromeAppearance(inputs: .init(tint: tint, systemScheme: .dark))
            XCTAssertEqual(glass.veil, tint == .automatic ? nil : tint)
            let opaque = resolveChromeAppearance(inputs: .init(tint: tint, systemScheme: .dark,
                reduceTransparency: true, increasedContrast: true))
            XCTAssertNil(opaque.veil)
            XCTAssertNotNil(opaque.fill)
            XCTAssertEqual(opaque.material, .opaque)
            XCTAssertEqual(opaque.separatorWidth, 2)
        }
        let solid = resolveChromeAppearance(inputs: .init(appearance: .custom, solidColor: .white,
            tint: .black, reduceTransparency: true))
        XCTAssertEqual(solid.material, .solid)
        XCTAssertEqual(solid.scheme, .light)
        XCTAssertEqual(solid.fill, .white)
    }
    func testExplicitThemeWinsOverSystemTintAndAccessibility() {
        for theme in [AppAppearance.light, .dark] {
            let expected: ColorScheme = theme == .dark ? .dark : .light
            for system in [ColorScheme.light, .dark] {
                for tint in WorkspaceSidebarFrostedTint.allCases {
                    for opaque in [false, true] {
                        let resolved = resolveChromeAppearance(inputs: .init(theme: theme, tint: tint,
                            systemScheme: system,
                            reduceTransparency: opaque, increasedContrast: true))
                        XCTAssertEqual(resolved.scheme, expected)
                        XCTAssertEqual(resolved.material, opaque ? .opaque : .glass)
                    }
                }
            }
        }
    }

    func testThemeParsesAndRejectsInvalidValues() {
        XCTAssertEqual(parseConfig("").config.appearance, .system)
        for theme in AppAppearance.allCases {
            let parsed = parseConfig("appearance = '\(theme.rawValue)'")
            XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
            XCTAssertEqual(parsed.config.appearance, theme)
        }
        for invalid in ["'auto'", "'Dark'", "true", "42"] {
            XCTAssertFalse(parseConfig("appearance = \(invalid)").errors.isEmpty)
        }
        XCTAssertNil(AppAppearance.system.nativeAppearance)
        XCTAssertEqual(AppAppearance.light.nativeAppearance?.name, .aqua)
        XCTAssertEqual(AppAppearance.dark.nativeAppearance?.name, .darkAqua)
    }

    func testNativeExpandedSurfaceUsesResolvedAppearanceAndOneMaterial() {
        var configuration = WorkspaceSidebarConfiguration.empty
        configuration.alwaysExpanded = true
        configuration.appearance = .system
        configuration.heightMode = .centered
        let container = WorkspaceSidebarMaterialContainer(frame: CGRect(x: 0, y: 0, width: 240, height: 400), reduceTransparency: { false })
        for scheme in [ColorScheme.light, .dark] {
            configuration.frostedTint = .automatic
            container.configure(configuration: configuration, visibleWidth: 240, contentColorScheme: scheme)
            XCTAssertEqual(container.appearance?.name, scheme == .dark ? .darkAqua : .aqua)
            XCTAssertEqual(container.subviews.filter { !$0.isHidden }.count, 1)
        }
        for theme in [AppAppearance.light, .dark] {
            configuration.theme = theme
            container.configure(configuration: configuration, visibleWidth: 240,
                wallpaperTone: theme == .dark ? .light : .dark,
                contentColorScheme: theme == .dark ? .light : .dark)
            XCTAssertEqual(container.appearance?.name, theme == .dark ? .darkAqua : .aqua)
        }
    }
}

@MainActor
final class HelperChromeAppearanceTest: WorkspaceTestCase {
    func testNativeLayerAppearanceRefreshReusesLayersAndClearReleasesThem() throws {
        let compositor = WindowResizePreviewCompositorView(frame: .init(x: 0, y: 0, width: 300, height: 200))
        let item = WindowResizePreviewItem(id: 1, frame: .init(x: 0, y: 0, width: 300, height: 200),
            appName: "Fixture", icons: [], isTabGroup: true, drawsFrameOnly: false, frameOnlyHeaderHeight: 20)
        config.appearance = .light
        compositor.update([item], presentation: .detailed)
        let layer = try XCTUnwrap(compositor.layer?.sublayers?.first as? WindowResizePreviewItemLayer)
        let light = layer.palette.fill
        for _ in 0..<20 {
            config.appearance = .dark
            compositor.refreshAppearance()
            XCTAssertTrue(compositor.layer?.sublayers?.first === layer)
            XCTAssertNotEqual(layer.palette.fill, light)
            config.appearance = .light
            compositor.refreshAppearance()
            XCTAssertEqual(layer.palette.fill, light)
        }
        compositor.clear()
        XCTAssertTrue(compositor.layer?.sublayers?.isEmpty ?? true)
        compositor.refreshAppearance()
        XCTAssertTrue(compositor.layer?.sublayers?.isEmpty ?? true)
    }

    func testLayerPaletteResolvesAllThemesAccessibilityAndCustomColor() {
        for theme in AppAppearance.allCases {
            for system in [ColorScheme.light, .dark] {
                for opaque in [false, true] {
                    for contrast in [false, true] {
                        let resolved = resolveChromeAppearance(inputs: .init(theme: theme, systemScheme: system,
                            reduceTransparency: opaque, increasedContrast: contrast))
                        let palette = ResizePreviewPalette(appearance: resolved, increasedContrast: contrast)
                        XCTAssertEqual(palette.fill.alpha, 1)
                        XCTAssertGreaterThanOrEqual(palette.stroke.alpha, contrast ? 0.35 : 0.12)
                        let components = palette.fill.components ?? []
                        XCTAssertFalse(components.isEmpty)
                    }
                }
            }
        }
        let white = ResizePreviewPalette(appearance: resolveChromeAppearance(inputs: .init(appearance: .custom, solidColor: .white)), increasedContrast: false)
        let black = ResizePreviewPalette(appearance: resolveChromeAppearance(inputs: .init(appearance: .custom, solidColor: .black)), increasedContrast: false)
        XCTAssertNotEqual(white.fill, black.fill)
        XCTAssertNotEqual(white.stroke, black.stroke)
    }
}
