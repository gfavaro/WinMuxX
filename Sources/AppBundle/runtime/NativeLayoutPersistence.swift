import Foundation
import Common

/// A separate namespace. No native restore changes display ownership, launches
/// apps, activates Spaces or consults the virtual workspace recovery file.
struct NativePersistedLayout: Codable, Equatable, Sendable {
    let root: FrozenContainer
    let floating: [FrozenWindow]
    let arrangement: WorkspaceLayoutName
    let preservesGroups: Bool
    let masterIndex: Int
    let masterRatio: CGFloat?

    @MainActor init(_ workspace: Workspace) {
        root = FrozenContainer(workspace.rootTilingContainer)
        floating = workspace.floatingWindows.map(FrozenWindow.init)
        arrangement = workspace.arrangement
        preservesGroups = workspace.preservesTopLevelGroups
        masterIndex = workspace.nativePersistentMasterGroupIndex
        masterRatio = workspace.masterRatio
    }

    var windows: [FrozenWindow] {
        func leaves(_ container: FrozenContainer) -> [FrozenWindow] {
            container.children.flatMap { child in
                switch child {
                    case .window(let window): [window]
                    case .container(let child): leaves(child)
                }
            }
        }
        return leaves(root) + floating
    }

    var supported: Bool {
        func supported(_ container: FrozenContainer) -> Bool {
            // The same layouts native tiling shows; tab groups stack, scrolling keeps edge columns.
            [.tiles, .dwindle, .tabGroup, .stacked].contains(container.layout) && container.children.allSatisfy {
                if case .container(let child) = $0 { return supported(child) }
                if case .window(let window) = $0 { return !window.isFullscreen }
                return false
            }
        }
        return [.dwindle, .master, .scrolling].contains(arrangement) && supported(root) &&
            floating.allSatisfy { !$0.isFullscreen } && Set(windows.map(\.id)).count == windows.count
    }
}

private struct NativeLayoutFile: Codable, Sendable {
    var version = 1
    var spaces: [String: NativePersistedLayout] = [:]
}

private actor NativeLayoutStorage {
    let url: URL
    private var savedRevision: UInt64 = 0
    init(url: URL) { self.url = url }
    func load() throws -> [String: NativePersistedLayout] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let file = try JSONDecoder().decode(NativeLayoutFile.self, from: Data(contentsOf: url))
        guard file.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return file.spaces
    }
    func save(_ spaces: [String: NativePersistedLayout], revision: UInt64) throws {
        guard revision > savedRevision else { return }
        assertTestWriteIsTemporary(url)
        let data = try JSONEncoder().encode(NativeLayoutFile(spaces: spaces))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        savedRevision = revision
    }
}

@MainActor
final class NativeLayoutPersistence {
    private let storage: NativeLayoutStorage
    private var loaded = false
    private var loading: Task<[String: NativePersistedLayout], Error>?
    private var saveRevision: UInt64 = 0
    private var writable = true
    private var saved: [String: NativePersistedLayout] = [:]
    private var pending = Set<String>()
    private var arrangementApplied = Set<String>()
    private var firstAttempt: [String: ContinuousClock.Instant] = [:]
    private(set) var lastError: String?
    var now: () -> ContinuousClock.Instant = { .now }
    /// After a Mac restart window identities change and terminal titles move on, so a
    /// complete match may never come. Past this, the desktop is saved again as it is.
    var pendingGrace: Duration = .seconds(90)
    var pendingCount: Int { pending.count }

    init(url: URL? = nil) {
        let target = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(winMuxAppSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("native-space-layouts-v1.json")
        storage = NativeLayoutStorage(url: target)
    }

    func reconcile(_ layouts: NativeSpaceLayouts) async {
        guard config.nativeSpaces.restoreLayouts, !serverArgs.isReadOnly else { return }
        if !loaded {
            // A newer reconciliation can enter while the first load is awaiting
            // disk. All callers share that load; none may autosave before it ends.
            let storage = storage
            let request = loading ?? Task { try await storage.load() }
            loading = request
            do {
                let records = try await request.value
                if !loaded { saved = records; pending = Set(records.keys); loaded = true }
            } catch {
                writable = false
                loaded = true
                lastError = "Native layouts could not be read; file preserved: \(error)"
            }
            loading = nil
        }
        guard !Task.isCancelled, layouts.snapshot != nil else { return }
        for (uuid, workspace) in layouts.retainedByUUID where workspace.isVisible {
            guard pending.contains(uuid), let record = saved[uuid] else { continue }
            if restore(record, to: workspace) { pending.remove(uuid); continue }
            // macOS keeps a desktop's identity across restarts, so its arrangement is
            // restored even when its windows cannot all be matched.
            if arrangementApplied.insert(uuid).inserted, [.dwindle, .master, .scrolling].contains(record.arrangement),
               workspace.arrangement != record.arrangement {
                workspace.transitionArrangement(to: record.arrangement)
                workspace.masterRatio = record.masterRatio
            }
            let since = firstAttempt[uuid] ?? now()
            firstAttempt[uuid] = since
            if since.duration(to: now()) >= pendingGrace {
                // Windows that have not returned by now are not coming back: keep the rest,
                // unless the user has meanwhile chosen another arrangement for this desktop.
                if workspace.arrangement == record.arrangement { _ = restore(record, to: workspace, allowPartial: true) }
                pending.remove(uuid)
            }
        }
    }

    func save(_ layouts: NativeSpaceLayouts) async {
        guard loaded, writable, config.nativeSpaces.restoreLayouts, !serverArgs.isReadOnly, !Task.isCancelled else { return }
        var next = saved
        for (uuid, workspace) in layouts.retainedByUUID where !pending.contains(uuid) {
            next[uuid] = NativePersistedLayout(workspace)
        }
        guard next != saved else { return }
        saveRevision &+= 1
        let revision = saveRevision
        do {
            try await storage.save(next, revision: revision)
            if saveRevision == revision { saved = next; lastError = nil }
        } catch {
            if saveRevision == revision { lastError = "Native layouts could not be saved: \(error)" }
        }
    }

    /// Restore a uniquely matched tree. Only windows already on this desktop are ever
    /// matched, never another Space's. Missing windows leave the snapshot pending and
    /// protected from autosave; once its grace period ends, `allowPartial` restores
    /// the tree without them instead of discarding it.
    func restore(_ record: NativePersistedLayout, to workspace: Workspace, allowPartial: Bool = false) -> Bool {
        guard record.supported else { return false }
        let candidates = workspace.allLeafWindowsRecursive
        let live = candidates.compactMap { window in window.restartIdentity.map { (window.windowId, $0) } }
        let savedWindows = record.windows
        var matched: [UInt32: Window] = [:]
        for window in candidates {
            guard let identity = window.restartIdentity,
                  let oldID = matchRestartWindow(id: window.windowId, identity: identity, saved: savedWindows, live: live),
                  matched[oldID] == nil else { continue }
            matched[oldID] = window
        }
        pairRemainingByApp(saved: savedWindows, candidates: candidates, matched: &matched)
        guard matched.count == savedWindows.count || allowPartial && !matched.isEmpty else { return false }
        let previous = workspace.rootTilingContainer
        previous.unbindFromParent()
        restoreTreeRecursive(frozenContainer: record.root, parent: workspace, index: INDEX_BIND_LAST, windowsById: matched)
        let root = workspace.rootTilingContainer
        for frozen in record.floating {
            guard let window = matched[frozen.id] else { continue }
            applyFrozenWindowState(window, frozen)
            // Membership is already established by macOS. This only changes the
            // layout tree; floating windows keep their actual physical frame.
            window.bind(to: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
        // Preserve newly arrived windows and their nested groups as a whole.
        if !previous.allLeafWindowsRecursive.isEmpty {
            previous.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
        workspace.arrangement = record.arrangement
        workspace.preservesTopLevelGroups = record.preservesGroups
        workspace.masterRatio = record.masterRatio
        workspace.masterStackLayout = .tiles
        workspace.restoreNativeMasterGroupIndex(record.masterIndex)
        if matched.count < savedWindows.count { workspace.normalizeContainers() } // Drop groups left empty.
        return true
    }

    /// After a restart, process IDs change and terminal titles move on or repeat, so
    /// windows rarely match one by one. When an app has exactly as many unmatched
    /// windows here as it saved, they are paired in creation order: only their places
    /// in this desktop's layout depend on it.
    private func pairRemainingByApp(saved: [FrozenWindow], candidates: [Window], matched: inout [UInt32: Window]) {
        let used = Set(matched.values.map(\.windowId))
        let savedByApp = Dictionary(grouping: saved.filter { matched[$0.id] == nil && $0.restartIdentity != nil },
            by: { $0.restartIdentity!.bundleId })
        let liveByApp = Dictionary(grouping: candidates.filter { !used.contains($0.windowId) && $0.restartIdentity != nil },
            by: { $0.restartIdentity!.bundleId })
        for (app, savedWindows) in savedByApp {
            guard let liveWindows = liveByApp[app], liveWindows.count == savedWindows.count else { continue }
            for (old, window) in zip(savedWindows, liveWindows.sorted { $0.windowId < $1.windowId }) { matched[old.id] = window }
        }
    }
}
