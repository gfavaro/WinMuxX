@testable import AppBundle
import Foundation
import Common
import XCTest

@MainActor
final class ConfigurationSourceTest: WorkspaceTestCase {
    private func fixture(_ text: String) throws -> (URL, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "WinMuxX.ConfigurationSourceTest." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let file = directory.appending(path: "config.toml")
        try text.write(to: file, atomically: true, encoding: .utf8)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try FileManager.default.removeItem(at: directory)
        }
        return (file, defaults)
    }

    func testMinimumMigrationPreservesSparseNamesAndFillsExplicitSlots() throws {
        let original = """
        # User config
        config-version = 2
        persistent-workspaces = ['7', 'Code']
        minimum-workspace-count = 5
        [mode.main.binding]
        alt-j = 'focus dfs-next'
        """
        let migrated = try migratingLegacyMinimumWorkspaceCount(in: original)
        XCTAssertFalse(migrated.contains("minimum-workspace-count"))
        XCTAssertTrue(migrated.contains("# User config"))
        let parsed = parseConfig(migrated)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(Array(parsed.config.persistentWorkspaces), ["7", "Code", "1", "2", "3"])
        XCTAssertEqual(try migratingLegacyMinimumWorkspaceCount(in: migrated), migrated)
        XCTAssertEqual(Array(parseConfig(original).config.persistentWorkspaces), ["7", "Code", "1", "2", "3"])
    }

    func testSmallerMinimumDoesNotRewriteExplicitNamesOrComments() throws {
        let original = """
        config-version = 2
        persistent-workspaces = [
          '7', # primary task
          'Code'
        ]
        minimum-workspace-count = 1
        """
        let migrated = try migratingLegacyMinimumWorkspaceCount(in: original)
        XCTAssertTrue(migrated.contains("# primary task"))
        XCTAssertEqual(Array(parseConfig(migrated).config.persistentWorkspaces), ["7", "Code"])
    }

    func testLegacyVersionOneBindingsSurviveUpgrade() throws {
        let migrated = try migratingLegacyMinimumWorkspaceCount(in: """
        minimum-workspace-count = 3
        [mode.main.binding]
        alt-7 = 'workspace 7'
        """)
        let parsed = parseConfig(migrated)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.configVersion, 2)
        XCTAssertEqual(Array(parsed.config.persistentWorkspaces), ["7", "1", "2"])
        XCTAssertFalse(parsed.config.modes[mainModeId]?.bindings.isEmpty ?? true)
    }

    func testQuotedMinimumKeysMigrateWithoutRecursion() throws {
        for key in [#""minimum-workspace-count""#, #""minimum-workspace-\u0063ount""#] {
            let migrated = try migratingLegacyMinimumWorkspaceCount(in: key + " = 2")
            XCTAssertEqual(Array(parseConfig(migrated).config.persistentWorkspaces), ["1", "2"])
        }
    }

    func testInvalidLegacyMinimumCannotSilentlyChangeConfig() {
        for value in ["-1", "true", "'3'", "1.5", String(Int.max)] {
            XCTAssertThrowsError(try migratingLegacyMinimumWorkspaceCount(in: "minimum-workspace-count = \(value)"))
        }
    }

    func testPreferencesMigrateWithBackupAndTOMLWins() throws {
        let original = """
        config-version = 2
        minimum-workspace-count = 2
        [window-tabs]
        double-sided-windows = false
        [menu-bar]
        indicator = 'icon'
        """
        let (file, defaults) = try fixture(original)
        defaults.set(true, forKey: "doubleSidedWindows")
        defaults.set("workspace", forKey: "menuBarIndicator")
        defaults.set("monochrome", forKey: "iconAppearance")
        try migrateLegacyConfiguration(at: file, defaults: defaults)
        let text = try String(contentsOf: file, encoding: .utf8)
        let parsed = parseConfig(text)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertFalse(parsed.config.windowTabs.doubleSidedWindows)
        XCTAssertEqual(parsed.config.menuBar.indicator, .icon)
        XCTAssertEqual(parsed.config.menuBar.iconAppearance, .monochrome)
        XCTAssertEqual(Array(parsed.config.persistentWorkspaces), ["1", "2"])
        XCTAssertEqual(try String(contentsOf: file.appendingPathExtension("backup.1"), encoding: .utf8), original)
        for key in ["doubleSidedWindows", "menuBarIndicator", "iconAppearance"] {
            XCTAssertNil(defaults.object(forKey: key))
        }
        try migrateLegacyConfiguration(at: file, defaults: defaults)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.appendingPathExtension("backup.2").path))
    }

    func testRemovingImportedPreferenceUsesDefaultWithoutResurrection() throws {
        let (file, defaults) = try fixture("config-version = 2\n")
        defaults.set(true, forKey: "doubleSidedWindows")
        try migrateLegacyConfiguration(at: file, defaults: defaults)
        XCTAssertTrue(parseConfig(try String(contentsOf: file, encoding: .utf8)).config.windowTabs.doubleSidedWindows)
        try ConfigFileStore.edit(at: file) {
            removeSettingsConfigValue(in: $0, section: "window-tabs", key: "double-sided-windows")
        }
        try migrateLegacyConfiguration(at: file, defaults: defaults)
        XCTAssertFalse(parseConfig(try String(contentsOf: file, encoding: .utf8)).config.windowTabs.doubleSidedWindows)
    }

    func testFailedMigrationPreservesOriginalAndLegacyPreferences() throws {
        let original = "config-version = 2\nunknown-key = true\n"
        let (file, defaults) = try fixture(original)
        defaults.set(true, forKey: "doubleSidedWindows")
        XCTAssertThrowsError(try migrateLegacyConfiguration(at: file, defaults: defaults))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original)
        XCTAssertEqual(defaults.object(forKey: "doubleSidedWindows") as? Bool, true)
    }

    func testSettingsEditsAndRawTOMLHaveTheSameConfiguration() {
        let text = applyingSettingsConfigEdits([
            .init(section: "menu-bar", key: "indicator", renderedValue: "'workspace'"),
            .init(section: "menu-bar", key: "icon-appearance", renderedValue: "'monochrome'"),
            .init(section: "window-tabs", key: "double-sided-windows", renderedValue: "true"),
        ], to: "config-version = 2\n")
        let parsed = parseConfig(text)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.menuBar.indicator, .workspace)
        XCTAssertEqual(parsed.config.menuBar.iconAppearance, .monochrome)
        XCTAssertTrue(parsed.config.windowTabs.doubleSidedWindows)
        for bad in ["[menu-bar]\nindicator = 'number'", "[menu-bar]\nicon-appearance = true",
                    "[window-tabs]\ndouble-sided-windows = 'true'"] {
            XCTAssertFalse(parseConfig(bad).errors.isEmpty)
        }
    }

    func testReloadPublishesMenuPreferencesAndDryRunDoesNot() async throws {
        let (file, _) = try fixture("""
        config-version = 2
        [menu-bar]
        indicator = 'workspace'
        icon-appearance = 'monochrome'
        [window-tabs]
        double-sided-windows = true
        """)
        let savedMenu = TrayMenuModel.shared.menuBarConfiguration
        defer { TrayMenuModel.shared.menuBarConfiguration = savedMenu }
        let loaded = try await reloadConfig(forceConfigUrl: file)
        XCTAssertTrue(loaded)
        XCTAssertEqual(TrayMenuModel.shared.menuBarConfiguration, config.menuBar)
        XCTAssertEqual(config.menuBar.indicator, .workspace)
        XCTAssertTrue(config.windowTabs.doubleSidedWindows)
        try "config-version = 2\n".write(to: file, atomically: true, encoding: .utf8)
        var args = ReloadConfigCmdArgs(rawArgs: [])
        args.dryRun = true
        args.noGui = true
        var output = ""
        let validated = try await reloadConfig(args: args, forceConfigUrl: file, stdout: &output)
        XCTAssertTrue(validated)
        XCTAssertEqual(config.menuBar.indicator, .workspace)
        XCTAssertEqual(TrayMenuModel.shared.menuBarConfiguration.indicator, .workspace)
        let reloaded = try await reloadConfig(forceConfigUrl: file)
        XCTAssertTrue(reloaded)
        XCTAssertEqual(config.menuBar.indicator, .icon)
        XCTAssertFalse(config.windowTabs.doubleSidedWindows)
    }
}
