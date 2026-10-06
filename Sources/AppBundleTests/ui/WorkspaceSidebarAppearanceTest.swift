@testable import AppBundle
import AppKit
import Combine
import SwiftUI
import XCTest

@MainActor
final class WorkspaceSidebarAppearanceTest: XCTestCase {
    func testReduceTransparencyOverridesBothBackgroundToggleStates() {
        for enabled in [false, true] {
            XCTAssertEqual(WorkspaceSidebarSystemBackground.resolve(showBackground: enabled, reduceTransparency: true), .opaque)
        }
        XCTAssertEqual(WorkspaceSidebarSystemBackground.resolve(showBackground: false, reduceTransparency: false), .clear)
        XCTAssertEqual(WorkspaceSidebarSystemBackground.resolve(showBackground: true, reduceTransparency: false), .glass)
    }

    func testExpandedSidebarAlwaysUsesFrostedBackgroundUnlessTransparencyIsReduced() {
        for showBackground in [false, true] {
            XCTAssertEqual(WorkspaceSidebarSystemBackground.resolve(showBackground: showBackground, reduceTransparency: false, expanded: true), .frosted)
            XCTAssertEqual(WorkspaceSidebarSystemBackground.resolve(showBackground: showBackground, reduceTransparency: true, expanded: true), .opaque)
        }
    }

    func testBackgroundToggleOnlyControlsCollapsedSystemSidebar() {
        let container = WorkspaceSidebarMaterialContainer(frame: .init(x: 0, y: 0, width: 560, height: 200))
        var configuration = WorkspaceSidebarConfiguration.empty
        configuration.collapsedWidth = 44
        configuration.expandedWidth = 280

        configuration.menuBarBackground = false
        container.configure(configuration: configuration, visibleWidth: 44)
        XCTAssertTrue(container.activeSurface === container.clearSurface)
        container.configure(configuration: configuration, visibleWidth: 280)
        XCTAssertTrue(container.activeSurface === container.effect)

        configuration.menuBarBackground = true
        container.configure(configuration: configuration, visibleWidth: 44)
        XCTAssertTrue(container.activeSurface === (container.glassSurface ?? container.effect))
        container.configure(configuration: configuration, visibleWidth: 280)
        XCTAssertTrue(container.activeSurface === container.effect)
    }

    func testEachSidebarCanApplyItsOwnWallpaperContrast() {
        let container = WorkspaceSidebarMaterialContainer(frame: .init(x: 0, y: 0, width: 560, height: 200))
        var configuration = WorkspaceSidebarConfiguration.empty
        configuration.collapsedWidth = 44
        configuration.menuBarBackground = false
        container.configure(configuration: configuration, visibleWidth: 44, wallpaperTone: .light)
        XCTAssertEqual(container.appearance?.name, .aqua)
        container.configure(configuration: configuration, visibleWidth: 44, wallpaperTone: .dark)
        XCTAssertEqual(container.appearance?.name, .darkAqua)
    }

    func testSolidForegroundContrastForPresetsAndCustomColors() {
        XCTAssertEqual(workspaceSidebarSolidColorScheme(.white), .light)
        XCTAssertEqual(workspaceSidebarSolidColorScheme(.black), .dark)
        XCTAssertEqual(workspaceSidebarSolidColorScheme(ChromeSolidColor.yellow.color), .light)
        XCTAssertEqual(workspaceSidebarSolidColorScheme(ChromeSolidColor.midnight.color), .dark)
    }

    func testMenuBarBackgroundParsesAndDefaultsToTransparent() {
        let (legacy, errors) = parseConfig("[workspace-sidebar]\nbackground = 'menu-bar'\n")
        XCTAssertEqual(errors, [])
        XCTAssertFalse(legacy.workspaceSidebar.menuBarBackground)
        for enabled in [true, false] {
            let (parsed, errors) = parseConfig("[workspace-sidebar]\nmenu-bar-background = \(enabled)\n")
            XCTAssertEqual(errors, [])
            XCTAssertEqual(parsed.workspaceSidebar.menuBarBackground, enabled)
        }
        let (_, invalid) = parseConfig("[workspace-sidebar]\nmenu-bar-background = 'yes'\n")
        XCTAssertFalse(invalid.isEmpty)
    }

    func testSystemGlassUsesWallpaperContrastIndependentlyOfBackgroundToggle() {
        var layout = WorkspaceSidebarConfiguration.empty
        layout.appearance = .system
        layout.background = .menuBar
        layout.collapsedWidth = 44
        layout.expandedWidth = 240
        for width in [layout.collapsedWidth, layout.expandedWidth] {
            layout.menuBarBackground = false
            XCTAssertTrue(layout.usesWallpaperContrast(visibleWidth: width, reduceTransparency: false))
            layout.menuBarBackground = true
            XCTAssertTrue(layout.usesWallpaperContrast(visibleWidth: width, reduceTransparency: false))
            layout.menuBarBackground = false
            XCTAssertFalse(layout.usesWallpaperContrast(visibleWidth: width, reduceTransparency: true))
        }
        layout.appearance = .custom
        XCTAssertFalse(layout.usesWallpaperContrast(visibleWidth: 44, reduceTransparency: false))
    }

    func testCompactControlsFitEverySupportedRailWidth() {
        for width in [28, 36, 44, 50, 56, 120] {
            let metrics = WorkspaceSidebarCompactMetrics(width: CGFloat(width))
            XCTAssertLessThanOrEqual(metrics.badgeSize + 2 * metrics.innerInset, metrics.sectionWidth)
            XCTAssertLessThanOrEqual(metrics.sectionWidth + 2 * workspaceSidebarCompactRailHorizontalInset, CGFloat(width))
            XCTAssertGreaterThan(metrics.badgeSize, 0)
        }
    }

    func testCompactPresetsScaleControlsAndKeepMediumAtExistingSize() {
        let small = WorkspaceSidebarCompactMetrics(width: 36)
        let medium = WorkspaceSidebarCompactMetrics(width: 44)
        let large = WorkspaceSidebarCompactMetrics(width: 56)
        XCTAssertEqual(medium.fontSize, 18)
        XCTAssertEqual(medium.badgeSize, workspaceSidebarBadgeWidth)
        XCTAssertEqual(medium.headerHeight, workspaceSidebarWorkspaceSectionHeaderHeight)
        XCTAssertLessThan(small.fontSize, medium.fontSize)
        XCTAssertLessThan(medium.fontSize, large.fontSize)
        XCTAssertLessThan(small.headerHeight, medium.headerHeight)
        XCTAssertLessThan(medium.headerHeight, large.headerHeight)
    }

    func testConfigurationChangePublishesWithoutWorkspaceChanges() {
        let model = TrayMenuModel()
        var updates = 0
        let subscription = model.objectWillChange.sink { updates += 1 }
        var updated = WorkspaceSidebarConfiguration.empty
        updated.appearance = .custom
        updated.chromeStyle = .solid
        model.setIfChanged(\.workspaceSidebarConfiguration, updated)
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(workspaceSidebarSnapshot(from: model).configuration, updated)
        model.setIfChanged(\.workspaceSidebarConfiguration, updated)
        XCTAssertEqual(updates, 1)
        XCTAssertTrue(model.workspaceSidebarWorkspaces.isEmpty)
        withExtendedLifetime(subscription) {}
    }

    func testSystemAppearanceIsDefaultAndDoesNotChangeSharedChrome() {
        let (parsed, errors) = parseConfig("[workspace-sidebar]\nchrome-style = 'solid'\n")
        XCTAssertEqual(errors, [])
        XCTAssertEqual(parsed.workspaceSidebar.appearance, .system)
        XCTAssertEqual(parsed.workspaceSidebar.chromeStyle, .solid)
        XCTAssertEqual(WorkspaceSidebarConfiguration.empty.appearance, .system)
    }

    func testBothAppearanceOptionsParseAndPreserveChromeSettings() {
        for appearance in WorkspaceSidebarAppearance.allCases {
            let (parsed, errors) = parseConfig("""
                [workspace-sidebar]
                appearance = '\(appearance.rawValue)'
                chrome-style = 'solid'
                solid-chrome-color = 'green'
                """)
            XCTAssertEqual(errors, [])
            XCTAssertEqual(parsed.workspaceSidebar.appearance, appearance)
            XCTAssertEqual(parsed.workspaceSidebar.chromeStyle, .solid)
            XCTAssertEqual(parsed.workspaceSidebar.solidChromeColor, .green)
        }
    }

    func testInvalidAppearanceIsRejected() {
        for value in ["'native'", "true", "3"] {
            let (_, errors) = parseConfig("[workspace-sidebar]\nappearance = \(value)\n")
            XCTAssertFalse(errors.isEmpty)
        }
    }

    func testCustomChromeSupportsLegacyLiquidGlassKey() {
        let (parsed, errors) = parseConfig("""
            [workspace-sidebar]
            appearance = 'custom'
            use-liquid-glass = false
            """)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(parsed.workspaceSidebar.appearance, .custom)
        XCTAssertEqual(parsed.workspaceSidebar.chromeStyle, .solid)
    }

    func testSnapshotUsesSurfaceStyleAsOnlyAppearanceChoice() {
        let previous = config
        defer { config = previous }
        config.workspaceSidebar.chromeStyle = .solid
        config.workspaceSidebar.appearance = .custom
        let before = workspaceSidebarConfiguration()
        config.workspaceSidebar.appearance = .system
        XCTAssertEqual(workspaceSidebarConfiguration(), before)
        config.workspaceSidebar.chromeStyle = .liquidGlass
        let after = workspaceSidebarConfiguration()
        XCTAssertEqual(after.appearance, .system)
        XCTAssertEqual(after.chromeStyle, .liquidGlass)
        XCTAssertEqual(after.collapsedWidth, before.collapsedWidth)
        XCTAssertEqual(after.expandedWidth, before.expandedWidth)
    }

    func testNativeMaterialAndInactivePanelBehavior() {
        let view = NSVisualEffectView()
        WorkspaceSidebarVisualEffect().configure(view)
        XCTAssertEqual(view.material, .sidebar)
        XCTAssertEqual(view.blendingMode, .behindWindow)
        XCTAssertEqual(view.state, .active)
        XCTAssertFalse(view.isEmphasized)
        XCTAssertNil(view.appearance)
    }

    func testMaterialOnlyCoversVisibleRailOnBothSidesAndPreservesContentCoordinates() {
        let container = WorkspaceSidebarMaterialContainer(frame: .init(x: 0, y: 0, width: 560, height: 200))
        let content = NSView()
        container.install(content: content)
        var configuration = WorkspaceSidebarConfiguration.empty
        configuration.collapsedWidth = 44
        configuration.expandedWidth = 280
        for side in [WorkspaceSidebarPosition.left, .right] {
            configuration.position = side
            for width: CGFloat in [0, 44, 140, 280, 560] {
                container.configure(configuration: configuration, visibleWidth: width)
                let surface = container.activeSurface
                XCTAssertEqual(surface.frame.width, width)
                XCTAssertEqual(surface.isHidden, width == 0)
                XCTAssertTrue(content.isDescendant(of: surface))
                XCTAssertEqual(content.convert(CGPoint.zero, to: container), CGPoint.zero,
                    "Drop-target coordinates must stay relative to the full panel")
                XCTAssertEqual(surface.frame.minX, side == .left ? 0 : 560 - width)
            }
        }
        configuration.appearance = .custom
        container.configure(configuration: configuration, visibleWidth: 44)
        XCTAssertTrue(container.effect.isHidden)
        XCTAssertTrue(content.superview === container.customSurface)
        XCTAssertFalse(container.customSurface.isHidden)
    }

    func testNativeLabelUpdatesTextWithoutLosingSemanticColorOrAddingBackground() {
        let label = NSTextField(labelWithString: "1")
        let effect = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        effect.material = .sidebar
        effect.state = .active
        effect.addSubview(label)
        let window = NSWindow(contentRect: effect.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = effect
        WorkspaceSidebarNativeLabel(text: "Workspace 12", size: 15, weight: .semibold).configure(label)
        XCTAssertEqual(label.stringValue, "Workspace 12")
        XCTAssertEqual(label.textColor, .labelColor)
        XCTAssertFalse(label.drawsBackground)
        XCTAssertFalse(label.isEditable)
        XCTAssertTrue(label.superview === effect)
        WorkspaceSidebarNativeLabel(text: "Workspace 13", size: 15, weight: .regular, secondary: true).configure(label)
        XCTAssertEqual(label.stringValue, "Workspace 13")
        XCTAssertEqual(label.textColor, .secondaryLabelColor)
    }

    func testBackgroundDefaultsAndAllOptionsParse() {
        let (defaults, defaultErrors) = parseConfig("[workspace-sidebar]\n")
        XCTAssertEqual(defaultErrors, [])
        XCTAssertEqual(defaults.workspaceSidebar.background, .sidebar)
        XCTAssertEqual(WorkspaceSidebarConfiguration.empty.background, .sidebar)
        for background in WorkspaceSidebarBackground.allCases {
            let (parsed, errors) = parseConfig("[workspace-sidebar]\nbackground = '\(background.rawValue)'\n")
            XCTAssertEqual(errors, [])
            XCTAssertEqual(parsed.workspaceSidebar.background, background)
            XCTAssertEqual(parsed.workspaceSidebar.appearance, .system)
        }
        for value in ["'glass'", "true", "3"] {
            let (_, errors) = parseConfig("[workspace-sidebar]\nbackground = \(value)\n")
            XCTAssertFalse(errors.isEmpty)
        }
    }

    func testBackgroundSnapshotTriggersReloadWithoutChangingChrome() {
        let previous = config
        defer { config = previous }
        config.workspaceSidebar.background = .sidebar
        let before = workspaceSidebarConfiguration()
        config.workspaceSidebar.background = .transparent
        let after = workspaceSidebarConfiguration()
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after.background, .transparent)
        XCTAssertEqual(after.chromeStyle, before.chromeStyle)
        XCTAssertEqual(after.appearance, before.appearance)
    }

    func testMenuBarApproximationUsesNativeSidebarMaterial() {
        let view = NSVisualEffectView()
        WorkspaceSidebarVisualEffect(background: .menuBar).configure(view)
        XCTAssertEqual(view.material, .sidebar)
        XCTAssertEqual(view.blendingMode, .behindWindow)
        XCTAssertEqual(view.state, .active)
        WorkspaceSidebarVisualEffect(background: .sidebar).configure(view)
        XCTAssertEqual(view.material, .sidebar)
    }

    func testExpandedTransparentSurfaceRetainsBlurAndReducedOpacity() {
        let view = NSVisualEffectView()
        WorkspaceSidebarVisualEffect(frosted: true).configure(view)
        XCTAssertEqual(view.material, .hudWindow)
        XCTAssertEqual(view.blendingMode, .behindWindow)
        XCTAssertEqual(view.state, .active)
        XCTAssertEqual(view.alphaValue, 0.93, accuracy: 0.001)
        WorkspaceSidebarVisualEffect().configure(view)
        XCTAssertEqual(view.alphaValue, 1)
        XCTAssertEqual(view.material, .sidebar)
    }

    func testBackgroundEditPreservesCustomAppearanceAndBindings() {
        let updated = updateSettingsScalarConfig(
            in: "[workspace-sidebar]\nappearance = 'custom'\n[mode.main.binding]\nalt-h = 'focus left'\n",
            section: "workspace-sidebar", key: "background", renderedValue: "'menu-bar'"
        )
        let (parsed, errors) = parseConfig(updated)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(parsed.workspaceSidebar.background, .menuBar)
        XCTAssertEqual(parsed.workspaceSidebar.appearance, .custom)
        XCTAssertTrue(updated.contains("alt-h = 'focus left'"))
    }

    func testAppearanceEditPreservesOtherSettingsAndBindings() {
        let updated = updateSettingsScalarConfig(
            in: """
                [workspace-sidebar]
                chrome-style = 'solid'
                width = 300
                [mode.main.binding]
                alt-h = 'focus left'
                """,
            section: "workspace-sidebar",
            key: "appearance",
            renderedValue: "'custom'"
        )
        let (parsed, errors) = parseConfig(updated)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(parsed.workspaceSidebar.appearance, .custom)
        XCTAssertEqual(parsed.workspaceSidebar.chromeStyle, .solid)
        XCTAssertEqual(parsed.workspaceSidebar.width, 300)
        XCTAssertTrue(updated.contains("alt-h = 'focus left'"))
    }

    func testSemanticTextAndCustomPalette() {
        let system = WorkspaceSidebarPalette(appearance: .system)
        let label = Color(nsColor: .labelColor)
        XCTAssertEqual(system.foreground, label)
        XCTAssertEqual(system.text(opacity: 0.9), label.opacity(0.9))
        XCTAssertEqual(system.text(opacity: 0.4), label.opacity(0.4))
        XCTAssertEqual(system.text(opacity: 0), .clear)
        let highContrast = WorkspaceSidebarPalette(appearance: .system, increasedContrast: true)
        XCTAssertEqual(highContrast.text(opacity: 0.4), label.opacity(1))
        let custom = WorkspaceSidebarPalette(appearance: .custom)
        XCTAssertEqual(custom.foreground, .white)
        XCTAssertEqual(custom.text(opacity: 0.4), .white.opacity(0.4))
    }
}
