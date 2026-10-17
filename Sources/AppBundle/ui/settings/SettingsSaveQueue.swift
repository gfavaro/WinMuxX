import Foundation

/// Own committed writes independently of the view that submitted them.
@MainActor
final class SettingsSaveQueue {
    private var tail: Task<Void, Never>?

    func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }
}

/// Structured edits and reloads are injectable; ConfigFileStore still owns transactions.
@MainActor
struct SettingsConfigAccess {
    var edit: ((String) throws -> String) throws -> URL
    var reload: (URL) async throws -> Bool

    static var native: Self {
        Self(edit: { transform in
            let url = preferredEditableConfigUrl()
            try ConfigFileStore.edit(at: url, transform)
            return url
        }, reload: { try await reloadConfig(forceConfigUrl: $0) })
    }
}

extension ShortcutSettingsModel {
    func enqueueSettingsSave(
        ids: Set<String>, title: String?, retry: @escaping @MainActor () -> Void,
        operation: @escaping @MainActor () async throws -> Void,
    ) {
        saveQueue.enqueue { [self] in
            savingSettingIDs.formUnion(ids)
            defer { savingSettingIDs.subtract(ids) }
            retrySettingsSave = nil
            failedSettingID = nil
            failedSettingTitle = nil
            errorMessage = nil
            do {
                try await operation()
            } catch {
                retrySettingsSave = retry
                errorMessage = error.localizedDescription
                failedSettingID = ids.sorted().first
                failedSettingTitle = title
                failedSaveRevision += 1
            }
        }
    }
}
