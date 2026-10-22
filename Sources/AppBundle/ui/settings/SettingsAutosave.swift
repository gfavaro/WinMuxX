import SwiftUI

/// One cancelable debounce per field; accepted writes belong to SettingsSaveQueue.
private struct SettingsAutosaveKey<Value: Equatable>: Equatable {
    let value: Value
    let enabled: Bool
}

private struct SettingsAutosaveModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let enabled: Bool
    let commit: () -> Void
    func body(content: Content) -> some View {
        content
            .task(id: SettingsAutosaveKey(value: value, enabled: enabled)) {
                guard enabled else { return }
                do { try await Task.sleep(for: .milliseconds(650)) }
                catch { return }
                guard !Task.isCancelled else { return }
                commit()
            }
            .onDisappear { if enabled { commit() } }
    }
}

extension View {
    func settingsAutosave<Value: Equatable>(value: Value, enabled: Bool = true, commit: @escaping () -> Void) -> some View {
        modifier(SettingsAutosaveModifier(value: value, enabled: enabled, commit: commit))
    }
}
