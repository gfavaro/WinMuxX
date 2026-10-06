import AppKit
import Common
import Foundation

private let persistedFrozenWorldVersion = 2
@MainActor private var pendingRestartSnapshots: [PendingRestartSnapshot] = []
@MainActor private var restartMatchedWindows: [[UInt32: Window]] = []
@MainActor private var pendingRestartSave: Task<Void, Never>?
@MainActor private var lastRestartIdentityRefresh: Date = .distantPast
private struct RestartWindowAttempt {
    let generation: UInt64
    let started: Date
    var lastAttempt: Date = .distantPast
}
@MainActor private var restartWindowAttempts: [UInt32: RestartWindowAttempt] = [:]
@MainActor private var restartRetryTask: Task<Void, Never>?

struct PendingRestartSnapshot: Codable, Sendable {
    let world: FrozenWorld
    var remainingWindowIds: Set<UInt32>
}

struct PersistedFrozenWorldEnvelope: Codable {
    let version: Int
    let world: FrozenWorld
    let pending: [PendingRestartSnapshot]?
}

@MainActor
private func persistedFrozenWorldUrl() throws -> URL {
    let appSupport = try FileManager.default.url(for: .applicationSupportDirectory,
        in: .userDomainMask, appropriateFor: nil, create: true)
    let directory = appSupport.appendingPathComponent(winMuxAppSupportDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("window-state.json")
}

@MainActor
func persistFrozenWorldForRestartIfPossible() {
    pendingRestartSave?.cancel()
    pendingRestartSave = nil
    guard !isUnitTest, isWinMuxRuntimeReady, !serverArgs.isReadOnly else { return }
    do {
        let url = try persistedFrozenWorldUrl()
        try saveRestartEnvelope(makeRestartEnvelope(), to: url)
    } catch {
        NSLog("WinMuxX: unable to save workspace state: %@", error.localizedDescription)
    }
}

@MainActor
func makeRestartEnvelope() -> PersistedFrozenWorldEnvelope {
    let world = FrozenWorld(workspaces: orderedWorkspacesForPresentation().filter { !$0.isArchived }.map(FrozenWorkspace.init),
        monitors: monitors.map(FrozenMonitor.init),
        windowIds: Workspace.all.flatMap { collectAllWindowIds(workspace: $0) }.toSet())
    return PersistedFrozenWorldEnvelope(version: persistedFrozenWorldVersion, world: world,
        pending: pendingRestartSnapshots.filter { !$0.remainingWindowIds.isEmpty })
}

func saveRestartEnvelope(_ envelope: PersistedFrozenWorldEnvelope, to url: URL) throws {
    let data = try JSONEncoder.winMuxDefault.encode(envelope)
    if let previous = try? Data(contentsOf: url),
       let decoded = try? JSONDecoder().decode(PersistedFrozenWorldEnvelope.self, from: previous),
       (1...persistedFrozenWorldVersion).contains(decoded.version) {
        try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
    }
    try data.write(to: url, options: .atomic)
}

func loadRestartEnvelope(from url: URL) -> PersistedFrozenWorldEnvelope? {
    for candidate in [url, url.appendingPathExtension("backup")] {
        guard let data = try? Data(contentsOf: candidate),
              let envelope = try? JSONDecoder().decode(PersistedFrozenWorldEnvelope.self, from: data),
              (1...persistedFrozenWorldVersion).contains(envelope.version) else { continue }
        return envelope
    }
    return nil
}

@MainActor
func schedulePersistedFrozenWorldSave() {
    guard !isUnitTest, isWinMuxRuntimeReady, !serverArgs.isReadOnly,
          TrayMenuModel.shared.isEnabled,
          NSWorkspace.shared.frontmostApplication?.bundleIdentifier != lockScreenAppBundleId else { return }
    // Capture current titles without adding AX round trips to every focus/layout event.
    guard pendingRestartSave == nil else { return }
    pendingRestartSave = Task { @MainActor in
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        if Date.now.timeIntervalSince(lastRestartIdentityRefresh) >= 5 {
            lastRestartIdentityRefresh = .now
            for window in MacWindow.allWindows {
                guard !Task.isCancelled else { return }
                if let identity = try? await window.macApp.getRestartWindowIdentity(window.windowId),
                   MacWindow.allWindowsMap[window.windowId] === window {
                    window.restartIdentity = identity
                }
            }
        }
        guard !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != lockScreenAppBundleId else {
            pendingRestartSave = nil
            return
        }
        pendingRestartSave = nil
        persistFrozenWorldForRestartIfPossible()
    }
}

@discardableResult
@MainActor
func loadPersistedFrozenWorldForStartupIfPresent() -> Bool {
    guard !serverArgs.isReadOnly, config.automaticallyTileNewWindows else { return false }
    do {
        let url = try persistedFrozenWorldUrl()
        if let envelope = loadRestartEnvelope(from: url) {
            preparePersistedFrozenWorldForStartup(envelope)
            return true
        }
    } catch { NSLog("WinMuxX: unable to load workspace state: %@", error.localizedDescription) }
    return false
}

@MainActor
func preparePersistedFrozenWorldForStartup(_ envelope: PersistedFrozenWorldEnvelope) {
    pendingRestartSnapshots = (envelope.pending ?? []) + [PendingRestartSnapshot(world: envelope.world,
        remainingWindowIds: envelope.world.windowIds)]
    for index in pendingRestartSnapshots.indices {
        let identifiable = pendingRestartSnapshots[index].world.workspaces.flatMap { collectFrozenWindows($0).values }
            .filter { $0.restartIdentity != nil }.map(\.id)
        pendingRestartSnapshots[index].remainingWindowIds.formIntersection(identifiable)
    }
    restartMatchedWindows = pendingRestartSnapshots.map { _ in [:] }
    // Create every saved destination before new-window rules or pruning can take its slot.
    for (index, snapshot) in pendingRestartSnapshots.enumerated() {
        for saved in snapshot.world.workspaces {
            if index < pendingRestartSnapshots.count - 1,
               Set(collectFrozenWindows(saved).keys).isDisjoint(with: snapshot.remainingWindowIds) { continue }
            let workspace = Workspace.get(byName: saved.name)
            workspace.assignProject(saved.projectId)
            workspace.restoreNamingStyle(saved.namingStyle)
            workspace.restoredDisplayIndex = saved.displayIndex
            workspace.preferredMonitorPoint = saved.monitor.preferredPoint(in: monitors)
        }
    }
}

@MainActor
func workspaceHasPendingRestartWindows(_ name: String) -> Bool {
    pendingRestartSnapshots.contains { snapshot in
        snapshot.world.workspaces.contains { workspace in
            workspace.name == name && !Set(collectFrozenWindows(workspace).keys)
                .intersection(snapshot.remainingWindowIds).isEmpty
        }
    }
}

@MainActor
func discardPendingRestartWindows(forWorkspace name: String) {
    for index in pendingRestartSnapshots.indices {
        let ids = pendingRestartSnapshots[index].world.workspaces.filter { $0.name == name }
            .flatMap { collectFrozenWindows($0).keys }
        pendingRestartSnapshots[index].remainingWindowIds.subtract(ids)
    }
}

@MainActor
var pendingRestartWindowCount: Int {
    pendingRestartSnapshots.reduce(0) { $0 + $1.remainingWindowIds.count }
}

@MainActor
func trackPendingRestartWindow(_ window: Window) {
    guard let bundleId = window.restartIdentity?.bundleId,
          pendingRestartSnapshots.contains(where: { snapshot in
              snapshot.world.workspaces.contains { workspace in
                  collectFrozenWindows(workspace).values.contains {
                      snapshot.remainingWindowIds.contains($0.id) && $0.restartIdentity?.bundleId == bundleId
                  }
              }
          }) else { return }
    restartWindowAttempts[window.windowId] = RestartWindowAttempt(generation: window.bindingGeneration, started: .now)
    guard !isUnitTest, restartRetryTask == nil else { return }
    restartRetryTask = Task { @MainActor in
        defer { restartRetryTask = nil }
        while !restartWindowAttempts.isEmpty {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            restartWindowAttempts = restartWindowAttempts.filter { Date.now.timeIntervalSince($0.value.started) < 30 }
            guard !Task.isCancelled else { return }
            if !restartWindowAttempts.isEmpty, isWinMuxRuntimeReady, TrayMenuModel.shared.isEnabled,
               NSWorkspace.shared.frontmostApplication?.bundleIdentifier != lockScreenAppBundleId {
                scheduleRefreshSession(.workspaceRestoration)
            }
        }
    }
}

@MainActor
func forgetPendingRestartWindow(_ id: UInt32) {
    restartWindowAttempts.removeValue(forKey: id)
}

/// Some apps expose an empty/transient title or document while launching. Retry
/// briefly, but stop as soon as placement changes; user/new-window rules win then.
@MainActor
func retryPendingRestartWindows() async throws {
    for id in Array(restartWindowAttempts.keys) {
        guard var attempt = restartWindowAttempts[id] else { continue }
        guard let window = Window.get(byId: id), window.bindingGeneration == attempt.generation,
              Date.now.timeIntervalSince(attempt.started) < 30 else {
            forgetPendingRestartWindow(id)
            continue
        }
        guard Date.now.timeIntervalSince(attempt.lastAttempt) >= 1 else { continue }
        attempt.lastAttempt = .now
        restartWindowAttempts[id] = attempt
        if let macWindow = window as? MacWindow,
           let identity = try? await macWindow.macApp.getRestartWindowIdentity(id) {
            window.restartIdentity = identity
        }
        guard window.bindingGeneration == attempt.generation else {
            forgetPendingRestartWindow(id)
            continue
        }
        if try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: window) {
            forgetPendingRestartWindow(id)
        }
    }
}

/// An app quitting (including during logout) must not erase its last destinations.
/// Explicitly closing a window in a running app does not keep a stale assignment.
@MainActor
func rememberRestartWindowBeforeAppTermination(_ window: Window) {
    guard window.restartIdentity != nil, let workspace = window.nodeWorkspace else { return }
    let world = FrozenWorld(workspaces: [FrozenWorkspace(workspace)], monitors: [], windowIds: [window.windowId])
    pendingRestartSnapshots.append(PendingRestartSnapshot(world: world, remainingWindowIds: [window.windowId]))
    restartMatchedWindows.append([:])
}

@MainActor
func restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow window: Window) async throws -> Bool {
    guard let identity = window.restartIdentity else { return false }
    let generation = window.bindingGeneration
    let candidates = pendingRestartSnapshots.indices.flatMap { index in
        pendingRestartSnapshots[index].world.workspaces.flatMap { workspace in
            collectFrozenWindows(workspace).values
                .filter { pendingRestartSnapshots[index].remainingWindowIds.contains($0.id) }
                .map { (snapshotIndex: index, workspace: workspace, window: $0) }
        }
    }
    let saved = candidates.map(\.window)
    guard !saved.isEmpty else { return false }
    let live: [(UInt32, RestartWindowIdentity)]
    if let macWindow = window as? MacWindow {
        live = (try? await macWindow.macApp.restartWindowIdentities()) ?? []
    } else {
        live = Workspace.all.flatMap { $0.allLeafWindowsRecursive }.compactMap {
            guard let identity = $0.restartIdentity else { return nil }
            return ($0.windowId, identity)
        }
    }
    guard let candidateIndex = matchRestartWindowIndex(id: window.windowId, identity: identity,
        saved: saved, live: live), Window.get(byId: window.windowId) === window,
        window.bindingGeneration == generation else { return false }
    let candidate = candidates[candidateIndex]
    let index = candidate.snapshotIndex
    let frozen = candidate.window
    let savedId = frozen.id
    let savedWorkspace = candidate.workspace
    // An app may reopen after the user moved/renamed the destination's project.
    // Its current workspace metadata takes precedence over the old snapshot.
    let existing = Workspace.existing(byName: savedWorkspace.name)
    let workspace = existing ?? Workspace.get(byName: savedWorkspace.name)
    if existing == nil {
        workspace.assignProject(savedWorkspace.projectId)
        workspace.restoreNamingStyle(savedWorkspace.namingStyle)
        workspace.restoredDisplayIndex = savedWorkspace.displayIndex
        workspace.preferredMonitorPoint = savedWorkspace.monitor.preferredPoint(in: monitors)
    }
    applyFrozenWindowState(window, frozen)
    if savedWorkspace.floatingWindows.contains(where: { $0.id == savedId }) {
        window.bindAsFloatingWindow(to: workspace)
    } else if savedWorkspace.macosUnconventionalWindows.contains(where: { $0.id == savedId }) {
        try await restoreFrozenUnconventionalWindow(window, frozen, on: workspace)
    } else {
        window.bind(to: workspace.rootTilingContainer, adaptiveWeight: frozen.weight, index: INDEX_BIND_LAST)
    }
    if _isStartup == true { restartMatchedWindows[index][savedId] = window }
    pendingRestartSnapshots[index].remainingWindowIds.remove(savedId)
    return true // The new-window placement rules must not override this destination.
}

@MainActor
func finalizePersistedFrozenWorldAfterRefresh(aliveWindowIds: Set<UInt32>) async throws {
    // Only rebuild whole trees during startup. Late app launches must not replay old
    // layouts over windows the user has already moved during the current session.
    guard isStartup else { return }
    for index in pendingRestartSnapshots.indices {
        let matched = restartMatchedWindows[index].filter { aliveWindowIds.contains($0.value.windowId) }
        guard let trigger = matched.values.first else { continue }
        let snapshot = pendingRestartSnapshots[index].world
        let workspaces = index == pendingRestartSnapshots.count - 1 ? snapshot.workspaces : snapshot.workspaces.filter {
            !Set(collectFrozenWindows($0).keys).isDisjoint(with: Set(matched.keys))
        }
        let world = FrozenWorld(workspaces: workspaces, monitors: snapshot.monitors, windowIds: Set(matched.keys))
        _ = try await restoreFrozenWorldIfNeeded(world, newlyDetectedWindow: trigger,
            matchedWindows: matched, restoreVisibleWorkspaces: index == pendingRestartSnapshots.count - 1)
    }
    restartMatchedWindows = pendingRestartSnapshots.map { _ in [:] }
}

@MainActor
func resetPersistedFrozenWorldForTests() {
    pendingRestartSave?.cancel()
    pendingRestartSave = nil
    pendingRestartSnapshots = []
    restartMatchedWindows = []
    lastRestartIdentityRefresh = .distantPast
    restartWindowAttempts = [:]
    restartRetryTask?.cancel()
    restartRetryTask = nil
}
