import Foundation

private let workspaceSidebarSectionHeader = "[workspace-sidebar]"

func updateWorkspaceSidebarLabelConfig(
    in configText: String,
    workspaceName: String,
    label: String?,
) -> String {
    updateWorkspaceSidebarKeyValueSectionConfig(
        in: configText,
        sectionHeader: "[workspace-sidebar.workspace-labels]",
        key: workspaceName,
        value: label,
    )
}

func updateWorkspaceSidebarProjectLabelConfig(
    in configText: String,
    projectId: String,
    label: String?,
) -> String {
    updateWorkspaceSidebarKeyValueSectionConfig(
        in: configText,
        sectionHeader: "[workspace-sidebar.project-labels]",
        key: projectId,
        value: label,
    )
}

func updateWorkspaceSidebarProjectColorConfig(
    in configText: String,
    projectId: String,
    colorHex: String?,
) -> String {
    updateWorkspaceSidebarKeyValueSectionConfig(
        in: configText,
        sectionHeader: "[workspace-sidebar.project-colors]",
        key: projectId,
        value: colorHex,
    )
}

private func updateWorkspaceSidebarKeyValueSectionConfig(
    in configText: String,
    sectionHeader: String,
    key: String,
    value: String?,
) -> String {
    let lines = configText.components(separatedBy: "\n")
    guard case let (sectionIndex, sectionEnd)? = tomlSectionBounds(in: lines, header: sectionHeader) else {
        guard let value else { return configText }
        return appendingTomlSection(to: configText, header: sectionHeader, line: tomlWorkspaceSidebarKeyValueLine(key: key, value: value))
    }

    var resultLines = Array(lines[..<sectionIndex])
    resultLines.append(lines[sectionIndex])

    var wroteValue = false
    var bodyLines: [String] = []
    for line in lines[(sectionIndex + 1)..<sectionEnd] {
        if workspaceSidebarLabelKey(in: line) == key {
            if let value, !wroteValue {
                bodyLines.append(tomlWorkspaceSidebarKeyValueLine(key: key, value: value))
                wroteValue = true
            }
            continue
        }
        bodyLines.append(line)
    }
    if let value, !wroteValue {
        bodyLines.append(tomlWorkspaceSidebarKeyValueLine(key: key, value: value))
    }

    let hasAnyEntries = bodyLines.contains(where: { workspaceSidebarLabelKey(in: $0) != nil })
    if hasAnyEntries {
        resultLines.append(contentsOf: bodyLines)
    } else {
        resultLines.removeLast()
        if !resultLines.isEmpty, resultLines.last?.isEmpty == false {
            resultLines.append("")
        }
    }
    resultLines.append(contentsOf: lines[sectionEnd...])
    return resultLines.joined(separator: "\n")
}

/// Index of `header` and the index of the next table header (or `lines.endIndex`).
private func tomlSectionBounds(in lines: [String], header: String) -> (header: Int, end: Int)? {
    guard let sectionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else { return nil }
    let sectionEnd = lines[(sectionIndex + 1)...]
        .firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }) ?? lines.endIndex
    return (sectionIndex, sectionEnd)
}

/// Appends a new table separated from existing content by one blank line.
private func appendingTomlSection(to configText: String, header: String, line: String) -> String {
    var result = configText
    if !result.isEmpty, !result.hasSuffix("\n") {
        result += "\n"
    }
    if !result.isEmpty {
        result += "\n"
    }
    result += "\(header)\n"
    result += line
    return result
}

@MainActor
func persistWorkspaceSidebarLabel(workspaceName: String, label: String?) throws {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    try ConfigFileStore.edit(at: targetUrl) { currentText in
        updateWorkspaceSidebarLabelConfig(in: currentText, workspaceName: workspaceName, label: label)
    }
}

@MainActor
func persistWorkspaceSidebarProjectLabel(projectId: String, label: String?) throws {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    try ConfigFileStore.edit(at: targetUrl) { currentText in
        updateWorkspaceSidebarProjectLabelConfig(in: currentText, projectId: projectId, label: label)
    }
}

@MainActor
func persistWorkspaceSidebarProjectColor(projectId: String, colorHex: String?) throws {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    try ConfigFileStore.edit(at: targetUrl) { currentText in
        updateWorkspaceSidebarProjectColorConfig(in: currentText, projectId: projectId, colorHex: colorHex)
    }
}

@MainActor
private func preferredWorkspaceSidebarConfigUrl() -> URL {
    preferredEditableConfigUrl()
}

private func workspaceSidebarLabelKey(in line: String) -> String? {
    workspaceSidebarConfigKey(in: line)
}

private func workspaceSidebarConfigKey(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
    let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
    if key.hasPrefix("\""), key.hasSuffix("\""), key.count >= 2 {
        let inner = key.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
    return String(key)
}

private func trailingTomlComment(in line: String) -> String? {
    guard let hashIndex = line.firstIndex(of: "#") else { return nil }
    return String(line[hashIndex...]).trimmingCharacters(in: .whitespaces)
}

private func tomlWorkspaceSidebarKeyValueLine(key: String, value: String) -> String {
    "\"\(tomlEscape(key))\" = \"\(tomlEscape(value))\""
}

private func tomlEscape(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
