import AppKit
import Common
import SwiftUI

struct SettingsModeOptionsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var selected = mainModeId
    @State private var newModeName = ""

    init(model: ShortcutSettingsModel, initialMode: String = mainModeId) {
        self.model = model
        _selected = State(initialValue: initialMode)
    }

    var body: some View {
        Section("Binding modes") {
            Picker("Mode", selection: $selected) {
                ForEach(config.modes.keys.sorted(), id: \.self) { Text($0).tag($0) }
            }.accessibilityIdentifier("settings.mode.selection")
            if config.modes[selected] != nil {
                SettingsModeFields(model: model, name: selected).id(selected)
            }
            HStack {
                TextField("New mode name", text: $newModeName)
                    .accessibilityIdentifier("settings.mode.new-name")
                Button("Add mode") {
                    let name = newModeName.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.activeSettingTitle = "Binding mode"
                    persistSettingsDocumentEdit(model: model, settingIDs: ["mode"], onSaved: {
                        selected = name
                        newModeName = ""
                    }) { current in try addingSettingsMode(name, to: current) }
                }.disabled(newModeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.savingSettingIDs.contains("mode"))
            }
            SettingsDescription("Modes use the shortcuts defined in Configuration. New modes include Escape to return to main; add an entry shortcut there when ready.")
        }
        .onChange(of: model.settingsRevision) { _ in
            if config.modes[selected] == nil { selected = mainModeId }
        }
    }
}

private struct SettingsModeFields: View {
    @ObservedObject var model: ShortcutSettingsModel
    let name: String
    @ObservedObject private var drafts: SettingsDraftStore
    init(model: ShortcutSettingsModel, name: String) {
        self.model = model
        self.name = name
        _drafts = ObservedObject(wrappedValue: model.drafts)
    }
    private var mode: Mode { config.modes[name] ?? .zero }
    private var prefix: String { "mode." + settingsQuotedString(name) }

    private func binding<T: Equatable>(_ key: String, fallback: @escaping @MainActor () -> T) -> Binding<T> {
        Binding(get: { drafts.value(for: prefix + "." + key, fallback: fallback) },
                set: { value in
                    let id = prefix + "." + key
                    if value == fallback() { drafts.acknowledge(drafts.entries.filter { $0.key == id }) }
                    else { drafts.set(value, for: id) }
                })
    }
    private func persist(_ key: String, _ value: String?) {
        let id = prefix + "." + key
        model.activeSettingTitle = "Mode \(name): \(key)"
        let submitted = drafts.entries.filter { $0.key == id }
        persistSettingsDocumentEdit(model: model, settingIDs: [id], submittedDrafts: submitted) { current in
            try updatingSettingsMode(name, key: key, value: value, in: current)
        }
    }

    var body: some View {
        if name == mainModeId {
            SettingsDescription("Main is the default mode. It never times out or shows a mode indicator.")
        } else {
            SettingsStepper("Inactivity timeout", id: prefix + ".timeout-ms",
                            value: binding("timeout-ms", fallback: { mode.timeoutMs }), range: 0...60000,
                            help: "0 keeps the mode active until you leave it. Accepted shortcuts restart the timeout after their commands finish.", unit: "ms") {
                let value: Int = drafts.value(for: prefix + ".timeout-ms", fallback: { mode.timeoutMs })
                persist("timeout-ms", String(value))
            }
            SettingsToggle("Show mode indicator", id: prefix + ".show-indicator",
                           isOn: binding("show-indicator", fallback: { mode.showIndicator }),
                           help: "Tint the menu-bar icon, or append the mode's first letter to the workspace indicator.") {
                let value: Bool = drafts.value(for: prefix + ".show-indicator", fallback: { mode.showIndicator })
                persist("show-indicator", String(value))
            }
            let color = binding("indicator-color", fallback: { mode.indicatorColor ?? "" })
            Toggle("Use system accent color", isOn: Binding(get: { color.wrappedValue.isEmpty }, set: { system in
                color.wrappedValue = system ? "" : "#5E9EFF"
                persist("indicator-color", system ? nil : settingsQuotedString(color.wrappedValue))
            })).accessibilityIdentifier(prefix + ".system-accent")
                .accessibilityLabel("Use system accent color")
            if !color.wrappedValue.isEmpty {
                ColorPicker("Mode color", selection: Binding(get: {
                    let hex = normalizedWorkspaceSidebarColorHex(color.wrappedValue) ?? "#5E9EFF"
                    let raw = UInt32(hex.dropFirst(), radix: 16) ?? 0
                    return Color(red: Double(raw >> 16 & 255) / 255, green: Double(raw >> 8 & 255) / 255, blue: Double(raw & 255) / 255)
                }, set: { value in
                    let rgb = NSColor(value).usingColorSpace(.sRGB) ?? .systemBlue
                    color.wrappedValue = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                    persist("indicator-color", settingsQuotedString(color.wrappedValue))
                }), supportsOpacity: false)
                SettingsTextField("Hex color", id: prefix + ".indicator-color", text: color,
                                  help: "Use six hexadecimal digits, for example #5E9EFF.", validate: {
                    normalizedWorkspaceSidebarColorHex($0) == nil ? "Use #RRGGBB." : nil
                }) {
                    if let hex = normalizedWorkspaceSidebarColorHex(color.wrappedValue) { persist("indicator-color", settingsQuotedString(hex)) }
                }
            }
        }
    }
}

@MainActor func addingSettingsMode(_ rawName: String, to text: String) throws -> String {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
        throw SettingsDisplayError("Enter a mode name without control characters.")
    }
    let parsed = parseConfig(text)
    guard parsed.errors.isEmpty else { throw SettingsDisplayError("Fix the configuration errors before adding a mode.") }
    guard parsed.config.modes[name] == nil else { throw SettingsDisplayError("A mode with this name already exists.") }
    let baseline = parsed.config.modes[mainModeId] == nil ? text + "\n[mode.main.binding]\n" : text
    return applyingSettingsConfigEdits([
        .init(section: "mode." + settingsQuotedString(name) + ".binding", key: "esc", renderedValue: settingsQuotedString("mode main")),
    ], to: baseline)
}

@MainActor func updatingSettingsMode(_ name: String, key: String, value: String?, in text: String) throws -> String {
    let parsed = parseConfig(text)
    guard parsed.errors.isEmpty, parsed.config.modes[name] != nil else {
        throw SettingsDisplayError("This mode is no longer available. Reload Settings before editing it.")
    }
    return applyingSettingsConfigEdits([
        .init(section: "mode." + settingsQuotedString(name), key: key, renderedValue: value),
    ], to: text)
}
