import Common
import Foundation

/// Window IDs and process IDs are reused. Never restore using an ID alone.
struct RecoveryWindowIdentity: Codable, Hashable, Sendable {
    let windowId: UInt32
    let pid: Int32
    let bundleId: String?
    let applicationLaunchDate: Date
}

struct RecoveryJournalOwner: Codable, Equatable {
    let pid: Int32
    let bundleId: String?
    let applicationLaunchDate: Date
}

struct RecoveryWindowEntry: Codable, Equatable {
    let identity: RecoveryWindowIdentity
    let originalFrame: CGRect

    var hasValidFrame: Bool {
        originalFrame.origin.x.isFinite && originalFrame.origin.y.isFinite &&
            originalFrame.width.isFinite && originalFrame.height.isFinite &&
            originalFrame.width > 0 && originalFrame.height > 0
    }
}

private struct RecoveryJournalFile: Codable {
    let version: Int
    let sessionId: UUID
    let owner: RecoveryJournalOwner
    let entries: [RecoveryWindowEntry]
}

/// A separate journal from window-state.json: resuming a layout is not crash recovery.
/// All access is serialized on the main actor; the file URL is injectable for tests.
@MainActor
final class WindowRecoveryJournal {
    private let url: URL
    private let owner: RecoveryJournalOwner
    private let sessionId = UUID()
    private(set) var entries: [UInt32: RecoveryWindowEntry] = [:]
    private(set) var carriedIds: Set<UInt32> = []
    private(set) var lastError: String?
    private(set) var canWrite = true
    private var lastSaveAttempt = Date.distantPast
    private var pendingSave: Task<Void, Never>?
    private let write: (Data, URL) throws -> Void

    init(url: URL, owner: RecoveryJournalOwner,
         write: @escaping (Data, URL) throws -> Void = { assertTestWriteIsTemporary($1); try $0.write(to: $1, options: .atomic) },
         isOwnerAlive: (RecoveryJournalOwner) -> Bool) {
        self.url = url
        self.owner = owner
        self.write = write
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let file = try JSONDecoder().decode(RecoveryJournalFile.self, from: Data(contentsOf: url))
            guard file.version == 1 else {
                canWrite = false
                lastError = "Unsupported recovery journal version; file preserved."
                return
            }
            guard !isOwnerAlive(file.owner) else {
                canWrite = false
                lastError = "Another running WinMux session owns the recovery journal; file preserved."
                return
            }
            guard Set(file.entries.map { $0.identity.windowId }).count == file.entries.count,
                  file.entries.allSatisfy(\.hasValidFrame) else {
                canWrite = false
                lastError = "Invalid recovery entries; file preserved."
                return
            }
            entries = Dictionary(uniqueKeysWithValues: file.entries.map { ($0.identity.windowId, $0) })
            carriedIds = Set(entries.keys)
        } catch {
            canWrite = false
            lastError = "Unable to read recovery journal; file preserved: \(error.localizedDescription)"
        }
    }

    /// Persist synchronously before the first frame write, not after a debounce that a crash
    /// could interrupt. Keep the original frame across repeated layout passes and restarts.
    func record(identity: RecoveryWindowIdentity, originalFrame: CGRect) {
        record([RecoveryWindowEntry(identity: identity, originalFrame: originalFrame)])
    }

    /// Flush all staged originals together before the first corresponding native
    /// mutation. Existing entries keep their original frame.
    func record(_ originals: [RecoveryWindowEntry]) {
        guard canWrite else { return }
        var changed = false
        for entry in originals where entry.hasValidFrame {
            let id = entry.identity.windowId
            guard entries[id]?.identity != entry.identity else { continue }
            carriedIds.remove(id)
            entries[id] = entry
            changed = true
        }
        if changed || (lastError != nil && Date().timeIntervalSince(lastSaveAttempt) >= 1) { save() }
    }

    func recoverableEntries(liveIdentities: [RecoveryWindowIdentity]) -> [RecoveryWindowEntry] {
        let live = Dictionary(liveIdentities.map { ($0.windowId, $0) }, uniquingKeysWith: { _, latest in latest })
        return carriedIds.sorted().compactMap { id in
            guard let entry = entries[id], live[id] == entry.identity else { return nil }
            return entry
        }
    }

    func forget(_ identity: RecoveryWindowIdentity, deferSave: Bool = false) {
        guard canWrite, entries[identity.windowId]?.identity == identity else { return }
        entries.removeValue(forKey: identity.windowId)
        carriedIds.remove(identity.windowId)
        if deferSave {
            guard pendingSave == nil else { return }
            pendingSave = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.save()
            }
        } else { save() }
    }

    func flushPendingChanges() {
        if pendingSave != nil { save() }
    }

    func retryFailedSaveIfNeeded() {
        if lastError != nil, Date().timeIntervalSince(lastSaveAttempt) >= 1 { save() }
    }

    isolated deinit { pendingSave?.cancel() }

    /// A clean quit doesn't need crash recovery for this session. Unresolved entries from
    /// an older crash remain available, including failures or disconnected displays.
    func finishCleanly(preserving identities: [RecoveryWindowIdentity] = []) {
        guard canWrite else { return }
        entries = entries.filter { carriedIds.contains($0.key) || identities.contains($0.value.identity) }
        save()
    }

    private func save() {
        pendingSave?.cancel()
        pendingSave = nil
        guard canWrite else { return }
        lastSaveAttempt = Date()
        do {
            if entries.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let file = RecoveryJournalFile(version: 1, sessionId: sessionId, owner: owner,
                                               entries: entries.values.sorted { $0.identity.windowId < $1.identity.windowId })
                try write(JSONEncoder().encode(file), url)
            }
            lastError = nil
        } catch {
            lastError = "Unable to save recovery journal: \(error.localizedDescription)"
        }
    }
}
