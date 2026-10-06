@testable import AppBundle
import SwiftUI
import XCTest

@MainActor
final class WorkspaceSidebarFrostedTintTest: XCTestCase {
    func testDefaultAndEveryTintParseWithoutChangingOtherChrome() {
        let (defaults, defaultErrors) = parseConfig("[workspace-sidebar]\n")
        XCTAssertEqual(defaultErrors, [])
        XCTAssertEqual(defaults.workspaceSidebar.frostedTint, .automatic)
        XCTAssertEqual(WorkspaceSidebarConfiguration.empty.frostedTint, .automatic)
        for tint in WorkspaceSidebarFrostedTint.allCases {
            let (parsed, errors) = parseConfig("""
                [workspace-sidebar]
                background = 'transparent'
                frosted-tint = '\(tint.rawValue)'
                chrome-style = 'solid'
                solid-chrome-color = 'green'
                """)
            XCTAssertEqual(errors, [])
            XCTAssertEqual(parsed.workspaceSidebar.frostedTint, tint)
            XCTAssertEqual(parsed.workspaceSidebar.background, .transparent)
            XCTAssertEqual(parsed.workspaceSidebar.chromeStyle, .solid)
            XCTAssertEqual(parsed.workspaceSidebar.solidChromeColor, .green)
        }
    }

    func testInvalidTintIsRejected() {
        for value in ["'invalid'", "false", "42"] {
            let (_, errors) = parseConfig("[workspace-sidebar]\nfrosted-tint = \(value)\n")
            XCTAssertFalse(errors.isEmpty)
        }
    }

    func testSnapshotReflectsTintChangeWithoutAffectingCompactContrast() {
        let previous = config
        defer { config = previous }
        config.workspaceSidebar.background = .transparent
        config.workspaceSidebar.frostedTint = .automatic
        let before = workspaceSidebarConfiguration()
        config.workspaceSidebar.frostedTint = .ice
        let after = workspaceSidebarConfiguration()
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after.frostedTint, .ice)
        XCTAssertEqual(after.background, before.background)
        XCTAssertEqual(after.chromeStyle, before.chromeStyle)
        XCTAssertTrue(before.usesWallpaperContrast(visibleWidth: before.collapsedWidth, reduceTransparency: false))
        XCTAssertFalse(after.usesWallpaperContrast(visibleWidth: after.collapsedWidth, reduceTransparency: false))
    }

    func testPaletteContainsAllPreviewColorsAndGradients() {
        XCTAssertNil(WorkspaceSidebarFrostedTint.automatic.preferredColorScheme)
        XCTAssertEqual(WorkspaceSidebarFrostedTint.automatic.colors(colorScheme: .dark), [.black])
        XCTAssertEqual(WorkspaceSidebarFrostedTint.ice.colors(colorScheme: .light), [.white, .cyan, .pink])
        XCTAssertEqual(WorkspaceSidebarFrostedTint.aurora.colors(colorScheme: .dark), [.black, .indigo, .purple])
        for tint in WorkspaceSidebarFrostedTint.allCases {
            XCTAssertFalse(tint.colors(colorScheme: .dark).isEmpty)
        }
        XCTAssertEqual(WorkspaceSidebarFrostedTint.ice.preferredColorScheme, .light)
        XCTAssertEqual(WorkspaceSidebarFrostedTint.aurora.preferredColorScheme, .dark)
    }

    func testAutomaticTintUsesWallpaperButManualTintIgnoresIt() {
        let sample = WorkspaceSidebarWallpaperSample(tone: .dark, red: 0.1, green: 0.2, blue: 0.8)
        XCTAssertEqual(WorkspaceSidebarFrostedTint.automatic.colors(colorScheme: .dark, wallpaperSample: sample), [sample.color])
        XCTAssertEqual(WorkspaceSidebarFrostedTint.automatic.colors(colorScheme: .light), [.white])
        XCTAssertEqual(WorkspaceSidebarFrostedTint.pink.colors(colorScheme: .dark, wallpaperSample: sample), [.pink])
        XCTAssertEqual(WorkspaceSidebarFrostedTint.ice.colors(colorScheme: .dark, wallpaperSample: sample), [.white, .cyan, .pink])
    }

    func testExpandedFrostVeilAddsContrastWithoutChangingTintResolution() {
        XCTAssertEqual(workspaceSidebarFrostedVeilOpacity(tint: .automatic, hasWallpaperSample: false), 0.14)
        XCTAssertEqual(workspaceSidebarFrostedVeilOpacity(tint: .automatic, hasWallpaperSample: true), 0.18)
        XCTAssertEqual(workspaceSidebarFrostedVeilOpacity(tint: .aurora, hasWallpaperSample: false), 0.18)
    }

    func testTintEditPreservesBackgroundAndShortcuts() {
        let updated = updateSettingsScalarConfig(
            in: "[workspace-sidebar]\nbackground = 'transparent'\n[mode.main.binding]\nalt-h = 'focus left'\n",
            section: "workspace-sidebar", key: "frosted-tint", renderedValue: "'aurora'"
        )
        let (parsed, errors) = parseConfig(updated)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(parsed.workspaceSidebar.frostedTint, .aurora)
        XCTAssertEqual(parsed.workspaceSidebar.background, .transparent)
        XCTAssertTrue(updated.contains("alt-h = 'focus left'"))
    }
}
