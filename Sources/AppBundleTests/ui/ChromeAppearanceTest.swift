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
