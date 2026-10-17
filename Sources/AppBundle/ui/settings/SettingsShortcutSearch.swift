import Foundation

func filteredShortcutSections(
    _ sections: [ShortcutSettingsModel.Section], assignments: [String: String], query: String,
) -> [ShortcutSettingsModel.Section] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return sections }
    return sections.compactMap { section in
        let actions = section.actions.filter { action in
            [action.title, action.subtitle ?? "", action.commandScript, action.canonicalCommand, assignments[action.id] ?? ""]
                .contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return actions.isEmpty ? nil : .init(id: section.id, category: section.category, title: section.title, summary: section.summary, actions: actions)
    }
}
