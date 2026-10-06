import Common
import Foundation
import TOMLKit

@MainActor
func persistSettingsConfig(section: String?, key: String, renderedValue: String, model: ShortcutSettingsModel, onSaved: (() -> Void)? = nil) {
    persistSettingsConfigEdits([SettingsConfigEdit(section: section, key: key, renderedValue: renderedValue)], model: model, onSaved: onSaved)
}

struct SettingsConfigEdit {
    let section: String?
    let key: String
    let renderedValue: String?
}

@MainActor
func persistSettingsConfigEdits(_ edits: [SettingsConfigEdit], model: ShortcutSettingsModel, draftIDs: Set<String> = [], draftSnapshot: [String: SettingsDraftStore.Entry]? = nil, onSaved: (() -> Void)? = nil) {
    let settingTitle = model.activeSettingTitle
    model.activeSettingTitle = nil
    let settingIDs = Set(edits.map { [$0.section, $0.key].compactMap { $0 }.joined(separator: ".") })
    let submittedDrafts = draftSnapshot ?? SettingsDraftStore.shared.entries.filter { settingIDs.union(draftIDs).contains($0.key) }
    let previousSave = model.pendingSettingsSave
    model.pendingSettingsSave = Task { @MainActor in
        await previousSave?.value
        model.savingSettingIDs.formUnion(settingIDs)
        defer { model.savingSettingIDs.subtract(settingIDs) }
        model.retrySettingsSave = nil
        model.failedSettingID = nil
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
            SettingsDraftStore.shared.acknowledge(submittedDrafts)
            onSaved?()
        } catch {
            model.retrySettingsSave = { [weak model] in
                guard let model else { return }
                model.activeSettingTitle = settingTitle
                persistSettingsConfigEdits(edits, model: model, draftIDs: draftIDs, draftSnapshot: submittedDrafts, onSaved: onSaved)
            }
            model.errorMessage = error.localizedDescription
            model.failedSettingID = edits.first.map { [$0.section, $0.key].compactMap { $0 }.joined(separator: ".") }
            model.failedSettingTitle = settingTitle
            model.failedSaveRevision += 1
        }
    }
}

func updateSettingsScalarConfig(in text: String, section: String?, key: String, renderedValue: String) -> String {
    editSettingsConfig(in: text, section: section, key: key, renderedValue: renderedValue)
}

func removeSettingsConfigValue(in text: String, section: String?, key: String) -> String {
    editSettingsConfig(in: text, section: section, key: key, renderedValue: nil)
}

private func editSettingsConfig(in text: String, section: String?, key: String, renderedValue: String?) -> String {
    var lines = text.components(separatedBy: "\n")
    let statements = settingsTomlStatements(lines)
    let target = (section.map(settingsTomlPath) ?? []) + settingsTomlPath(key)
    if let existing = statements.first(where: { $0.keyPath == target }) {
        let indent = String(lines[existing.start].prefix(while: \.isWhitespace))
        let comments = settingsTomlComments(lines[existing.start...existing.end].joined(separator: "\n"))
        var replacement = comments.map { indent + $0 }
        if let renderedValue {
            let originalLine = lines[existing.start]
            let originalKey = String(originalLine[..<settingsTomlEquals(originalLine)!]).trimmingCharacters(in: .whitespaces)
            replacement.append("\(indent)\(originalKey) = \(renderedValue)")
        }
        lines.replaceSubrange(existing.start...existing.end, with: replacement)
        return lines.joined(separator: "\n")
    }
    guard let renderedValue else { return text }
    // Use an existing parent table when possible. Otherwise write a dotted root
    // property: defining a second [table] after root dotted keys is illegal TOML.
    let parent = statements.filter {
        guard let header = $0.headerPath else { return false }
        return header.count < target.count && Array(target.prefix(header.count)) == header
    }.max { ($0.headerPath?.count ?? 0) < ($1.headerPath?.count ?? 0) }
    let prefixCount = parent?.headerPath?.count ?? 0
    let relativeKey = target.dropFirst(prefixCount).map(settingsTomlKey).joined(separator: ".")
    let insertion = parent.map { $0.end + 1 } ?? 0
    lines.insert("\(prefixCount == 0 ? "" : "    ")\(relativeKey) = \(renderedValue)", at: insertion)
    return lines.joined(separator: "\n")
}

private struct SettingsTomlStatement {
    let start: Int
    let end: Int
    let keyPath: [String]?
    let headerPath: [String]?
}

private func settingsTomlStatements(_ lines: [String]) -> [SettingsTomlStatement] {
    var result: [SettingsTomlStatement] = []
    var table: [String] = []
    var isArrayTable = false
    var line = 0
    while line < lines.count {
        let raw = lines[line].trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("[") {
            let clean = settingsTomlHeader(raw)
            isArrayTable = clean.hasPrefix("[[")
            let brackets = isArrayTable ? 2 : 1
            if clean.hasSuffix(String(repeating: "]", count: brackets)) {
                table = settingsTomlPath(String(clean.dropFirst(brackets).dropLast(brackets)))
                result.append(.init(start: line, end: line, keyPath: nil, headerPath: isArrayTable ? nil : table))
            }
            line += 1
        } else if !raw.hasPrefix("#"), let equal = settingsTomlEquals(raw) {
            let key = String(raw[..<equal])
            let value = String(raw[raw.index(after: equal)...])
            let tail = value + "\n" + lines.dropFirst(line + 1).joined(separator: "\n")
            let scan = scanSettingsTomlValue(tail)
            let end = min(line + scan.continuationLines, lines.count - 1)
            result.append(.init(start: line, end: end, keyPath: isArrayTable ? nil : table + settingsTomlPath(key), headerPath: nil))
            line = end + 1
        } else { line += 1 }
    }
    return result
}

private func settingsTomlHeader(_ raw: String) -> String {
    var quote: Character?
    var escaped = false
    for index in raw.indices {
        let c = raw[index]
        if let delimiter = quote {
            if escaped { escaped = false }
            else if c == "\\", delimiter == "\"" { escaped = true }
            else if c == delimiter { quote = nil }
        } else if c == "\"" || c == "'" { quote = c }
        else if c == "#" { return String(raw[..<index]).trimmingCharacters(in: .whitespaces) }
    }
    return raw.trimmingCharacters(in: .whitespaces)
}

private func settingsTomlEquals(_ value: String) -> String.Index? {
    var quote: Character?
    var escaped = false
    for index in value.indices {
        let c = value[index]
        if let delimiter = quote {
            if escaped { escaped = false }
            else if c == "\\", delimiter == "\"" { escaped = true }
            else if c == delimiter { quote = nil }
        } else if c == "\"" || c == "'" { quote = c }
        else if c == "=" { return index }
        else if c == "#" { return nil }
    }
    return nil
}

private func settingsTomlPath(_ raw: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var quote: Character?
    var escaped = false
    for c in raw {
        if let delimiter = quote {
            current.append(c)
            if escaped { escaped = false }
            else if c == "\\", delimiter == "\"" { escaped = true }
            else if c == delimiter { quote = nil }
        } else if c == "\"" || c == "'" { quote = c; current.append(c) }
        else if c == "." { parts.append(current); current = "" }
        else { current.append(c) }
    }
    parts.append(current)
    return parts.map {
        let token = $0.trimmingCharacters(in: .whitespaces)
        if token.hasPrefix("\"") || token.hasPrefix("'") {
            return (try? TOMLTable(string: "value = " + token))?["value"]?.string ?? token
        }
        return token
    }
}

private func settingsTomlKey(_ key: String) -> String {
    if key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) { return key }
    return "\"" + key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

private func settingsTomlComments(_ value: String) -> [String] {
    scanSettingsTomlValue(value, stopAtStatementEnd: false).comments
}

/// Scan arrays, inline tables and multiline strings without treating their
/// contents as section headers or keys. Keep comments when replacing a value.
private func scanSettingsTomlValue(_ raw: String, stopAtStatementEnd: Bool = true) -> (continuationLines: Int, comments: [String]) {
    let chars = Array(raw)
    var quote: Character?
    var triple = false
    var escaped = false
    var depth = 0
    var line = 0
    var comments: [String] = []
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if let delimiter = quote {
            if escaped { escaped = false }
            else if c == "\\", delimiter == "\"" { escaped = true }
            else if c == delimiter {
                if !triple { quote = nil }
                else if i + 2 < chars.count, chars[i + 1] == delimiter, chars[i + 2] == delimiter {
                    quote = nil; triple = false; i += 2
                }
            }
        } else if c == "#" {
            let start = i
            while i < chars.count, chars[i] != "\n" { i += 1 }
            comments.append(String(chars[start..<i]))
            continue
        } else if c == "\"" || c == "'" {
            quote = c
            triple = i + 2 < chars.count && chars[i + 1] == c && chars[i + 2] == c
            if triple { i += 2 }
        } else if c == "[" || c == "{" { depth += 1 }
        else if c == "]" || c == "}" { depth -= 1 }
        if c == "\n" {
            if quote == nil, depth == 0, stopAtStatementEnd { return (line, comments) }
            line += 1
        }
        i += 1
    }
    return (line, comments)
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
        if let value = edit.renderedValue {
            return updateSettingsScalarConfig(in: result, section: edit.section, key: edit.key, renderedValue: value)
        }
        return removeSettingsConfigValue(in: result, section: edit.section, key: edit.key)
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
