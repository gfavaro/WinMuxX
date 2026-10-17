import Foundation

func settingsQuotedString(_ value: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    // Encoding a Swift String cannot fail.
    return String(decoding: try! encoder.encode(value), as: UTF8.self)
}

/// Array-table boundaries come from the existing quote-aware statement scanner.
/// Text outside the edited entry is never reconstructed from the parsed projection.
struct SettingsRuleDocument {
    struct Entry: Equatable {
        let range: Range<Int>
        let text: String
    }
    let text: String
    let entries: [Entry]

    init(_ text: String) {
        self.text = text
        let lines = text.components(separatedBy: "\n")
        let statements = settingsTomlStatements(lines)
        entries = statements.compactMap { statement in
            guard statement.arrayHeaderPath == ["on-window-detected"] else { return nil }
            let end = statements.first { next in
                guard next.start > statement.start else { return false }
                if next.arrayHeaderPath != nil { return true }
                guard let path = next.headerPath else { return false }
                return path.first != "on-window-detected"
            }?.start ?? lines.count
            let range = statement.start..<end
            return Entry(range: range, text: lines[range].joined(separator: "\n"))
        }
    }

    func replacing(_ index: Int, with replacement: String?, in current: String) throws -> String {
        let latest = SettingsRuleDocument(current)
        guard entries.map(\.text) == latest.entries.map(\.text), latest.entries.indices.contains(index) else {
            throw ConfigFileStore.Conflict()
        }
        var lines = current.components(separatedBy: "\n")
        lines.replaceSubrange(latest.entries[index].range, with: replacement.map { $0.components(separatedBy: "\n") } ?? [])
        return lines.joined(separator: "\n")
    }

    func moving(_ index: Int, by offset: Int, in current: String) throws -> String {
        let latest = SettingsRuleDocument(current)
        let destination = index + offset
        guard entries.map(\.text) == latest.entries.map(\.text), entries.indices.contains(index),
              entries.indices.contains(destination), abs(offset) == 1 else { throw ConfigFileStore.Conflict() }
        var lines = current.components(separatedBy: "\n")
        // Replace from the end so earlier ranges remain stable.
        for i in [index, destination].sorted(by: >) {
            let other = i == index ? destination : index
            lines.replaceSubrange(latest.entries[i].range, with: entries[other].text.components(separatedBy: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    static func editing(_ block: String, edits: [SettingsConfigEdit]) throws -> String {
        let lines = block.components(separatedBy: "\n")
        let statements = settingsTomlStatements(lines)
        guard statements.first?.arrayHeaderPath == ["on-window-detected"] else { throw ConfigFileStore.Conflict() }
        var local = lines
        local[0] = "# Rule"
        for statement in statements {
            guard let header = statement.headerPath, header.first == "on-window-detected" else { continue }
            let path = header.dropFirst()
            guard path == ["if"] else { throw ConfigFileStore.Conflict() }
            guard local[statement.start].trimmingCharacters(in: .whitespaces).hasPrefix("[on-window-detected.if]") else { throw ConfigFileStore.Conflict() }
            local[statement.start] = local[statement.start].replacingOccurrences(of: "[on-window-detected.if]", with: "[if]")
        }
        var result = applyingSettingsConfigEdits(edits, to: local.joined(separator: "\n")).components(separatedBy: "\n")
        for statement in settingsTomlStatements(result) where statement.headerPath == ["if"] {
            result[statement.start] = result[statement.start].replacingOccurrences(of: "[if]", with: "[on-window-detected.if]")
        }
        // The original header (including its comment) remains in place.
        guard let marker = result.firstIndex(of: "# Rule") else { throw ConfigFileStore.Conflict() }
        result.remove(at: marker)
        result.insert(lines[0], at: 0)
        return result.joined(separator: "\n")
    }
}
