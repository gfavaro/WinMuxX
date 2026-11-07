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

/// Keys WinMuxX no longer reads. Each either accepted only one value or was an alias, so
/// dropping them changes nothing; `use-liquid-glass` becomes `chrome-style` unless that is set.
func removingRetiredConfigKeys(in text: String) throws -> String {
    var result = removingScrollingConfiguration(in: text)
    let table = try TOMLTable(string: result)
    for key in ["after-login-command", "non-empty-workspaces-root-containers-layout-on-startup",
                "indent-for-nested-containers-with-the-same-orientation"] where table[key] != nil {
        result = removeSettingsConfigValue(in: result, section: nil, key: key)
    }
    if let sidebar = table["workspace-sidebar"]?.table, let glass = sidebar["use-liquid-glass"]?.bool {
        result = removeSettingsConfigValue(in: result, section: "workspace-sidebar", key: "use-liquid-glass")
        if sidebar["chrome-style"] == nil {
            result = updateSettingsScalarConfig(in: result, section: "workspace-sidebar", key: "chrome-style",
                renderedValue: settingsQuotedString((glass ? ChromeStyle.liquidGlass : .solid).rawValue))
        }
    }
    // These options now have fixed behavior. Remove them before parsing so existing
    // user configuration remains loadable after the parser stops accepting them.
    let retiredPaths: Set<[String]> = [
        ["focus-follows-mouse-dwell"], ["drag-stack-layout"], ["tab-group-padding"],
        ["master", "ultrawide-mains"], ["master", "stack-layout"], ["window-tabs", "style"], ["hover-bar", "enabled"],
        ["workspace-swipe", "reverse-direction"], ["workspace-swipe", "animation-duration-ms"],
        ["workspace-sidebar", "hover-open-delay-ms"], ["workspace-sidebar", "menu-bar-reserve-height"],
        ["workspace-sidebar", "show-status-pills"], ["workspace-sidebar", "project-deletion-action"],
    ]
    for statement in settingsTomlStatements(result.components(separatedBy: "\n")) {
        guard let path = statement.keyPath,
              retiredPaths.contains(path) || path.last == "single-window-alignment" else { continue }
        let fullyQualifiedKey = path.map(settingsQuotedString).joined(separator: ".")
        result = removeSettingsConfigValue(in: result, section: nil, key: fullyQualifiedKey)
    }

    // The hover bar is fixed on, so its former table is no longer recognized.
    let lines = result.components(separatedBy: "\n")
    let statements = settingsTomlStatements(lines)
    guard !statements.contains(where: { $0.keyPath?.first == "hover-bar" }) else { return result }
    let headerLines = Set(statements.filter { $0.headerPath == ["hover-bar"] }.map(\.start))
    result = lines.enumerated().filter { !headerLines.contains($0.offset) }.map(\.element).joined(separator: "\n")
    return result
}

/// Scrolling workspaces moved to SpaceMuxX: the `[scrolling]` table, `scrolling.*` keys,
/// `layout = 'scrolling'` in workspace tables (which then use the default arrangement)
/// and shortcuts that run a scrolling command are removed. Line based, so comments stay.
func removingScrollingConfiguration(in text: String) -> String {
    var section = ""
    var lines: [String] = []
    for line in text.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") { section = trimmed }
        if section == "[scrolling]" || section.hasPrefix("[scrolling.") { continue }
        let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !trimmed.hasPrefix("#") else { lines.append(line); continue }
        let key = parts[0], value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        if section.isEmpty, key.hasPrefix("scrolling.") { continue }
        if section.hasPrefix("[workspace."), key == "layout", value == "scrolling" { continue }
        if section.hasPrefix("[mode."), let commands = bindingCommands(parts[1]) {
            let kept = commands.compactMap(withoutScrolling)
            if kept == commands { lines.append(line); continue }
            if kept.isEmpty { continue }
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
            let rendered = kept.count == 1 ? settingsQuotedString(kept[0]) : "[" + kept.map(settingsQuotedString).joined(separator: ", ") + "]"
            lines.append("\(indent)\(parts[0]) = \(rendered)")
            continue
        }
        lines.append(line)
    }
    return lines.joined(separator: "\n")
}

/// A binding's commands: one string or an array of strings, as TOML reads them. Anything
/// else is left exactly as written.
private func bindingCommands(_ rawValue: String) -> [String]? {
    guard let value = (try? TOMLTable(string: "v = \(rawValue)"))?["v"] else { return nil }
    if let command = value.string { return [command] }
    guard let array = value.array else { return nil }
    let commands = array.compactMap(\.string)
    return commands.count == array.count ? commands : nil
}

/// The command without scrolling: nil for a retired scrolling command, and `workspace-layout`
/// loses its `scrolling` choice (nil when nothing else is left). Its only flag takes a
/// window id, so a `scrolling` word there is always a layout choice.
private func withoutScrolling(_ command: String) -> String? {
    let words = command.split(separator: " ").map(String.init)
    let retired: Set = ["scrolling-center", "scrolling-width", "scrolling-minimap", "scrolling-focus", "scrolling-move", "scrolling-pin"]
    guard let name = words.first, !retired.contains(name) else { return nil }
    guard name == "workspace-layout" else { return command }
    let kept = words.filter { $0 != "scrolling" }
    return kept.contains(where: { $0 == "dwindle" || $0 == "master" }) ? kept.joined(separator: " ") : nil
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
        var result = try migratingLegacyMinimumWorkspaceCount(in: removingRetiredConfigKeys(in: current))
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
