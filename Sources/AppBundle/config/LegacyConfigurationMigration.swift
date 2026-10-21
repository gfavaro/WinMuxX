import Foundation
import TOMLKit

private struct ConfigurationMigrationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Compatibility import only: the runtime has no minimum-count setting.
/// The resulting explicit names are the complete workspace retention policy.
@MainActor
func migratingLegacyMinimumWorkspaceCount(in text: String) throws -> String {
    let table = try TOMLTable(string: text)
    guard let raw = table["minimum-workspace-count"] else { return text }
    guard let count = raw.int, count >= 0, count <= 4096 else {
        throw ConfigurationMigrationError(message: "Replace minimum-workspace-count with persistent-workspaces. Automatic migration supports integer counts from 0 to 4096.")
    }
    var result = removeSettingsConfigValue(in: text, section: nil, key: "minimum-workspace-count")
    guard try TOMLTable(string: result)["minimum-workspace-count"] == nil else {
        throw ConfigurationMigrationError(message: "Could not remove the legacy minimum-workspace-count key. Replace it with persistent-workspaces.")
    }
    let parsed = parseConfig(result) // The checked legacy key cannot recurse again.
    guard parsed.errors.isEmpty else {
        throw ConfigurationMigrationError(message: parsed.errors.map(\.description).joined(separator: "\n"))
    }
    var names = Array(parsed.config.persistentWorkspaces)
    var reserved = Set(names)
    var number = 1
    while names.count < count {
        let name = String(number)
        if reserved.insert(name).inserted { names.append(name) }
        number += 1
    }
    if names != Array(parsed.config.persistentWorkspaces) {
        result = updateSettingsScalarConfig(in: result, section: nil, key: "config-version", renderedValue: "2")
        result = updateSettingsScalarConfig(in: result, section: nil, key: "persistent-workspaces",
            renderedValue: "[" + names.map(settingsQuotedString).joined(separator: ", ") + "]")
    }
    return result
}

/// Import legacy preferences only when TOML does not already choose a value.
/// After the validated, backed-up write succeeds, removing the old keys prevents
/// a later TOML deletion from resurrecting an obsolete preference on next launch.
@MainActor
func migrateLegacyConfiguration(at url: URL, defaults: UserDefaults = .standard) throws {
    let keys = ["doubleSidedWindows", "menuBarIndicator", "iconAppearance"]
    let doubleSided = defaults.object(forKey: keys[0]) as? Bool
    let indicator = defaults.string(forKey: keys[1]).flatMap(MenuBarIndicator.init(rawValue:))
    let icon = defaults.string(forKey: keys[2]).flatMap(MenuBarIconAppearance.init(rawValue:))
    try ConfigFileStore.edit(at: url) { current in
        var result = try migratingLegacyMinimumWorkspaceCount(in: current)
        let table = try TOMLTable(string: result)
        if table["window-tabs"]?.table?["double-sided-windows"] == nil, let doubleSided {
            result = updateSettingsScalarConfig(in: result, section: "window-tabs", key: "double-sided-windows",
                renderedValue: doubleSided ? "true" : "false")
        }
        if table["menu-bar"]?.table?["indicator"] == nil, let indicator {
            result = updateSettingsScalarConfig(in: result, section: "menu-bar", key: "indicator",
                renderedValue: settingsQuotedString(indicator.rawValue))
        }
        if table["menu-bar"]?.table?["icon-appearance"] == nil, let icon {
            result = updateSettingsScalarConfig(in: result, section: "menu-bar", key: "icon-appearance",
                renderedValue: settingsQuotedString(icon.rawValue))
        }
        return result
    }
    for key in keys { defaults.removeObject(forKey: key) }
}
