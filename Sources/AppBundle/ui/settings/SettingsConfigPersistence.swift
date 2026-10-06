import Common
import Foundation

@MainActor
func persistSettingsConfig(section: String?, key: String, renderedValue: String, model: ShortcutSettingsModel, onSaved: (() -> Void)? = nil) {
    persistSettingsConfigEdits([SettingsConfigEdit(section: section, key: key, renderedValue: renderedValue)], model: model, onSaved: onSaved)
}

struct SettingsConfigEdit {
    let section: String?
    let key: String
    let renderedValue: String
}

@MainActor
func persistSettingsConfigEdits(_ edits: [SettingsConfigEdit], model: ShortcutSettingsModel, onSaved: (() -> Void)? = nil) {
    let settingTitle = model.activeSettingTitle
    model.activeSettingTitle = nil
    let previousSave = model.pendingSettingsSave
    model.pendingSettingsSave = Task { @MainActor in
        await previousSave?.value
        model.errorMessage = nil
        model.failedSettingTitle = nil
        do {
            let url = preferredEditableConfigUrl()
            let current = (try? String(contentsOf: url, encoding: .utf8)) ?? starterConfigText()
            let updated = applyingSettingsConfigEdits(edits, to: current)
            let parsed = parseConfig(updated)
            guard parsed.errors.isEmpty else {
                throw NSError(domain: "WinMux", code: 1, userInfo: [NSLocalizedDescriptionKey: parsed.errors.map(\.description).joined(separator: "\n")])
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updated.write(to: url, atomically: true, encoding: .utf8)
            guard try await reloadConfig(forceConfigUrl: url) else { throw NSError(domain: "WinMux", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saved the setting, but could not reload the config."]) }
            if model !== ShortcutSettingsModel.shared { model.reload() }
            onSaved?()
        } catch {
            model.errorMessage = error.localizedDescription
            model.failedSettingTitle = settingTitle
            model.failedSaveRevision += 1
        }
    }
}

func updateSettingsScalarConfig(in text: String, section: String?, key: String, renderedValue: String) -> String {
    let header = section.map { "[\($0)]" }
    var lines = text.components(separatedBy: "\n")
    let start: Int
    let end: Int
    if let header, let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) {
        start = index + 1
        end = lines[start...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) ?? lines.endIndex
    } else if let header {
        if lines.last?.isEmpty == false { lines.append("") }
        lines.append(header)
        lines.append("    \(key) = \(renderedValue)")
        return lines.joined(separator: "\n")
    } else {
        start = 0
        end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) ?? lines.endIndex
    }
    for index in start..<end where settingsKey(in: lines[index]) == key {
        let indent = String(lines[index].prefix(while: { $0.isWhitespace }))
        lines[index] = "\(indent)\(key) = \(renderedValue)"
        return lines.joined(separator: "\n")
    }
    lines.insert("\(section == nil ? "" : "    ")\(key) = \(renderedValue)", at: start)
    return lines.joined(separator: "\n")
}

private func settingsKey(in line: String) -> String? {
    let line = line.trimmingCharacters(in: .whitespaces)
    guard !line.hasPrefix("#"), let equal = line.firstIndex(of: "=") else { return nil }
    return String(line[..<equal]).trimmingCharacters(in: .whitespaces)
}

func tomlStringArray(_ text: String) -> String {
    let values = text.split(whereSeparator: \.isNewline).map { value in
        "\"\(value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
    return "[\(values.joined(separator: ", "))]"
}

func tomlCommaSeparatedStringArray(_ text: String) -> String {
    tomlStringArray(text.split(whereSeparator: { $0 == "," || $0.isNewline })
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }.joined(separator: "\n"))
}

func applyingSettingsConfigEdits(_ edits: [SettingsConfigEdit], to text: String) -> String {
    edits.reduce(text) { result, edit in
        updateSettingsScalarConfig(in: result, section: edit.section, key: edit.key, renderedValue: edit.renderedValue)
    }
}

func settingsGapValue(_ value: DynamicConfigValue<Int>, replacingDefaultWith defaultValue: Int) -> String {
    guard case .perMonitor(let overrides, _) = value else { return String(defaultValue) }
    let items = overrides.map { override in
        let monitor: String = switch override.description {
            case .main: "main"
            case .secondary: "secondary"
            case .sequenceNumber(let number): String(number)
            case .pattern(let pattern, _): pattern
        }
        let key = monitor.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "{ monitor.\"\(key)\" = \(override.value) }"
    } + [String(defaultValue)]
    return "[\(items.joined(separator: ", "))]"
}
