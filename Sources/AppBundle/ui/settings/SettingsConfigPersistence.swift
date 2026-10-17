import Foundation

@MainActor
func persistSettingsConfig(section: String?, key: String, renderedValue: String, model: ShortcutSettingsModel, onSaved: (() -> Void)? = nil) {
    persistSettingsConfigEdits([SettingsConfigEdit(section: section, key: key, renderedValue: renderedValue)], model: model, onSaved: onSaved)
}

@MainActor
func persistSettingsConfigEdits(_ edits: [SettingsConfigEdit], model: ShortcutSettingsModel, draftIDs: Set<String> = [], draftSnapshot: [String: SettingsDraftStore.Entry]? = nil, onSaved: (() -> Void)? = nil) {
    let settingIDs = Set(edits.map { [$0.section, $0.key].compactMap { $0 }.joined(separator: ".") })
    let submittedDrafts = draftSnapshot ?? model.drafts.entries.filter { settingIDs.union(draftIDs).contains($0.key) }
    persistSettingsDocumentEdit(model: model, settingIDs: settingIDs, submittedDrafts: submittedDrafts, onSaved: onSaved) {
        applyingSettingsConfigEdits(edits, to: $0)
    }
}

@MainActor
func persistSettingsDocumentEdit(model: ShortcutSettingsModel, settingIDs: Set<String>, submittedDrafts: [String: SettingsDraftStore.Entry] = [:], onSaved: (() -> Void)? = nil, edit: @escaping (String) throws -> String) {
    let settingTitle = model.activeSettingTitle
    model.activeSettingTitle = nil
    model.enqueueSettingsSave(ids: settingIDs, title: settingTitle, retry: { [weak model] in
        guard let model else { return }
        model.activeSettingTitle = settingTitle
        persistSettingsDocumentEdit(model: model, settingIDs: settingIDs, submittedDrafts: submittedDrafts, onSaved: onSaved, edit: edit)
    }) {
        let url = try model.configAccess.edit(edit)
        guard try await model.configAccess.reload(url) else { throw NSError(domain: "WinMux", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saved the setting, but could not reload the config."]) }
        if model !== ShortcutSettingsModel.shared { model.reload() }
        model.drafts.acknowledge(submittedDrafts)
        onSaved?()
    }
}
