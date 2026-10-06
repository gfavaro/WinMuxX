import SwiftUI

/// Keep user drafts across page changes and reloads without replacing view identity.
@MainActor
final class SettingsDraftStore: ObservableObject {
    struct Entry {
        let value: Any
        let matches: (Any) -> Bool
    }
    static let shared = SettingsDraftStore()
    @Published private(set) var entries: [String: Entry] = [:]

    func value<Value>(for id: String, fallback: @MainActor () -> Value) -> Value {
        entries[id]?.value as? Value ?? fallback()
    }

    func set<Value: Equatable>(_ value: Value, for id: String) {
        entries[id] = Entry(value: value, matches: { ($0 as? Value) == value })
    }

    func acknowledge(_ submitted: [String: Entry]) {
        for (id, entry) in submitted {
            if let current = entries[id], entry.matches(current.value) { entries.removeValue(forKey: id) }
        }
    }

    func refreshSavedValues() { objectWillChange.send() }
}

@propertyWrapper
@MainActor
struct SettingsDraft<Value: Equatable>: DynamicProperty {
    @ObservedObject private var store = SettingsDraftStore.shared
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
            store.set(newValue, for: id)
        }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

struct SettingsSaveSummary: View {
    @ObservedObject var model: ShortcutSettingsModel
    @ObservedObject private var drafts = SettingsDraftStore.shared
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
        } else if !drafts.entries.isEmpty || model.bindingsDraftRevision != model.savedBindingsRevision || model.configurationDraft != nil {
            Label("Unsaved changes", systemImage: "pencil").foregroundStyle(.secondary)
        }
    }
}
