@testable import AppBundle
import AppKit
import SwiftUI
import XCTest

@MainActor
final class ChromeAppearanceTest: XCTestCase {
    func testAutomaticAppearanceFollowsMonitorWithoutVeil() {
        for system in [ColorScheme.light, .dark] {
            for tone in [WorkspaceSidebarWallpaperTone.light, .dark] {
                let inputs = ChromeAppearanceInputs(systemScheme: system, menuBarScheme: system, wallpaperTone: tone)
                let result = resolveChromeAppearance(inputs: inputs)
                XCTAssertEqual(result.scheme, tone.colorScheme)
                XCTAssertEqual(result.material, .glass)
                XCTAssertNil(result.veil)
                XCTAssertNil(result.fill)
            }
        }
    }
    func testFallbackExplicitTintAndAccessibility() {
        XCTAssertEqual(resolveChromeAppearance(inputs: .init(systemScheme: .light, menuBarScheme: .dark)).scheme, .dark)
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
    }
}
