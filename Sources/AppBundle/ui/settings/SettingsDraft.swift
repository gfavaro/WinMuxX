import SwiftUI

/// Keep user drafts across page changes and reloads without replacing view identity.
@MainActor
@Observable
final class SettingsDraftStore {
    struct Entry {
        let value: Any
        let matches: (Any) -> Bool
    }
    static let shared = SettingsDraftStore()
    private(set) var entries: [String: Entry] = [:]

    /// Saved values come from the config, which views cannot observe: reading this makes a
    /// view that shows one redraw when the config is saved.
    private var savedValuesGeneration: UInt64 = 0

    func value<Value>(for id: String, fallback: @MainActor () -> Value) -> Value {
        _ = savedValuesGeneration
        return entries[id]?.value as? Value ?? fallback()
    }

    func set<Value: Equatable>(_ value: Value, for id: String) {
        entries[id] = Entry(value: value, matches: { ($0 as? Value) == value })
    }

    func acknowledge(_ submitted: [String: Entry]) {
        for (id, entry) in submitted {
            if let current = entries[id], entry.matches(current.value) { entries.removeValue(forKey: id) }
        }
    }

    func refreshSavedValues() { savedValuesGeneration &+= 1 }
}

@propertyWrapper
@MainActor
struct SettingsDraft<Value: Equatable>: DynamicProperty {
    private var store = SettingsDraftStore.shared
    private let id: String
    private let load: @MainActor () -> Value

    init(_ id: String, load: @escaping @MainActor () -> Value) {
        self.id = id
        self.load = load
    }

    var wrappedValue: Value {
        get { store.value(for: id, fallback: load) }
        nonmutating set {
            guard newValue != wrappedValue else { return }
            if newValue == load() {
                store.acknowledge(store.entries.filter { $0.key == id })
            } else {
                store.set(newValue, for: id)
            }
        }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

struct SettingsSaveSummary: View {
    var model: ShortcutSettingsModel
    var additionalUnsaved = false
    private var drafts: SettingsDraftStore
    init(model: ShortcutSettingsModel, additionalUnsaved: Bool = false) {
        self.model = model
        self.additionalUnsaved = additionalUnsaved
        self.drafts = model.drafts
    }
    var body: some View {
        if !model.savingSettingIDs.isEmpty {
            Label("Saving settings…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        } else if let error = model.errorMessage {
            VStack(alignment: .leading, spacing: 4) {
                Label("Could not save \(model.failedSettingTitle ?? "setting")", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                if let retry = model.retrySettingsSave {
                    SettingsDescription("Your changes have been kept. Review the field or retry the save.")
                    Button("Retry save", action: retry)
                }
                DisclosureGroup("Error details") { Text(error).textSelection(.enabled) }
            }
            .accessibilityElement(children: .contain)
        } else if additionalUnsaved || !drafts.entries.isEmpty || model.bindingsDraftRevision != model.savedBindingsRevision || model.configurationDraft != nil {
            Label("Unsaved changes", systemImage: "pencil").foregroundStyle(.secondary)
        }
    }
}
