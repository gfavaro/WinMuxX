import AppKit
import Common
import Foundation

@MainActor
final class WorkspaceRecoveryState {
    // AX becomes unobservable while the screen is locked. Keep the last world so
    // windows can return to their tree positions when AX becomes available again.
    var closedWindows = FrozenWorld(workspaces: [], monitors: [], windowIds: [])
    var pendingRestartSnapshots: [PendingRestartSnapshot] = []
    var restartMatchedWindows: [[UInt32: Window]] = []
    var lateRestartTreeDeadline: Date?
    var lateRestartTreeExpiry: Task<Void, Never>?
    var pendingRestartSave: Task<Void, Never>?
    var lastRestartIdentityRefresh: Date = .distantPast
    var restartWindowAttempts: [UInt32: RestartWindowAttempt] = [:]
    var restartRetryTask: Task<Void, Never>?
    var restartRestorationsInFlight = 0
    var firstUserWorkspaceSelectionDate: Date?
    let restartWriter = RestartStateWriter()

    func reset() {
        pendingRestartSave?.cancel()
        pendingRestartSave = nil
        pendingRestartSnapshots = []
        lateRestartTreeExpiry?.cancel()
        lateRestartTreeExpiry = nil
        lateRestartTreeDeadline = nil
        restartMatchedWindows = []
        lastRestartIdentityRefresh = .distantPast
        restartWindowAttempts = [:]
        firstUserWorkspaceSelectionDate = nil
        restartRetryTask?.cancel()
        restartRetryTask = nil
        closedWindows = FrozenWorld(workspaces: [], monitors: [], windowIds: [])
    }

    isolated deinit {
        pendingRestartSave?.cancel()
        lateRestartTreeExpiry?.cancel()
        restartRetryTask?.cancel()
    }
}

@MainActor private var recovery: WorkspaceRecoveryState { runtime.recovery }

private let persistedFrozenWorldVersion = 2

/// Once navigation begins, subsequently launched apps belong to the user's
/// selected workspace. Keep the first boundary so later navigation cannot make
/// an excluded process eligible again during delayed AX retries.
@MainActor
func recordUserWorkspaceSelectionForRestoration(at date: Date = .now) {
    guard _isStartup != true, isWinMuxRuntimeReady || isUnitTest else { return }
    if recovery.firstUserWorkspaceSelectionDate == nil {
        recovery.firstUserWorkspaceSelectionDate = date
    }
}

@MainActor
private func allowsSavedPlacement(_ identity: RestartWindowIdentity) -> Bool {
    guard let selection = recovery.firstUserWorkspaceSelectionDate else { return true }
    guard let launch = identity.launchDate else { return false }
    return launch <= selection
}

/// Only finish startup trees while no subsequent user layout change has occurred.
@MainActor
func invalidateLateRestartTreeRestoration() {
    guard isWinMuxRuntimeReady, _isStartup != true else { return }
    recovery.lateRestartTreeDeadline = nil
    recovery.lateRestartTreeExpiry?.cancel()
    recovery.lateRestartTreeExpiry = nil
    recovery.restartMatchedWindows = recovery.pendingRestartSnapshots.map { _ in [:] }
    compactPendingRestartSnapshots()
}

/// Snapshot indices are used across AX awaits. Compact only after all readers
/// have finished, and after the period that needs complete startup trees.
@MainActor
func compactPendingRestartSnapshots() {
    guard recovery.restartRestorationsInFlight == 0, _isStartup != true,
          recovery.lateRestartTreeDeadline == nil else { return }
    let snapshots = discardSupersededRestartAssignments(recovery.pendingRestartSnapshots)
    recovery.pendingRestartSnapshots = snapshots.filter { !$0.remainingWindowIds.isEmpty }
    recovery.restartMatchedWindows = recovery.pendingRestartSnapshots.map { _ in [:] }
}
struct RestartWindowAttempt {
    let generation: UInt64
    let started: Date
    var lastAttempt: Date = .distantPast
}

struct PendingRestartSnapshot: Codable, Equatable, Sendable {
    let world: FrozenWorld
    var remainingWindowIds: Set<UInt32>
}

private struct RestartProcessWindowKey: Hashable {
    let bundleId: String
    let pid: Int32
    let launchDate: Date
    let windowId: UInt32
}

/// Snapshots are ordered oldest to newest. A verified process/window identity
/// has only one current placement, regardless of changing terminal titles.
@MainActor
func discardSupersededRestartAssignments(_ snapshots: [PendingRestartSnapshot]) -> [PendingRestartSnapshot] {
    var result = snapshots
    var seen: Set<RestartProcessWindowKey> = []
    for index in result.indices.reversed() {
        for workspace in result[index].world.workspaces {
            for window in collectFrozenWindows(workspace).values {
                guard let identity = window.restartIdentity, let launchDate = identity.launchDate else { continue }
                let key = RestartProcessWindowKey(bundleId: identity.bundleId, pid: identity.pid,
                    launchDate: launchDate, windowId: window.id)
                if !seen.insert(key).inserted {
                    result[index].remainingWindowIds.remove(window.id)
                }
            }
        }
    }
    return result
}

struct PersistedFrozenWorldEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let world: FrozenWorld
    let pending: [PendingRestartSnapshot]?
}

@MainActor
private func persistedFrozenWorldUrl() throws -> URL {
    let appSupport = try FileManager.default.url(for: .applicationSupportDirectory,
        in: .userDomainMask, appropriateFor: nil, create: true)
    let directory = appSupport.appendingPathComponent(winMuxAppSupportDirectoryName, isDirectory: true)
    return directory.appendingPathComponent("window-state.json")
}

private func prepareRestartStateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    for file in [url, url.appendingPathExtension("backup")] where FileManager.default.fileExists(atPath: file.path) {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

@MainActor
func persistFrozenWorldForRestartIfPossible() {
    guard runtime.workspaceBackend.capabilities.usesVirtualRecovery else { return }
    recovery.pendingRestartSave?.cancel()
    recovery.pendingRestartSave = nil
    guard !isUnitTest, isWinMuxRuntimeReady, !serverArgs.isReadOnly else { return }
    do {
        let url = try persistedFrozenWorldUrl()
        try recovery.restartWriter.flush(makeRestartEnvelope(), to: url)
    } catch {
        NSLog("WinMuxX: unable to save workspace state: %@", error.localizedDescription)
    }
}

@MainActor
func makeRestartEnvelope() -> PersistedFrozenWorldEnvelope {
    compactPendingRestartSnapshots()
    let world = FrozenWorld(workspaces: orderedWorkspacesForPresentation().filter { !$0.isArchived }.map { FrozenWorkspace($0) },
        monitors: monitors.map(FrozenMonitor.init),
        windowIds: Workspace.all.flatMap { collectAllWindowIds(workspace: $0) }.toSet())
    let snapshots = discardSupersededRestartAssignments(recovery.pendingRestartSnapshots +
        [PendingRestartSnapshot(world: world, remainingWindowIds: world.windowIds)])
    return PersistedFrozenWorldEnvelope(version: persistedFrozenWorldVersion, world: world,
        pending: snapshots.dropLast().filter { !$0.remainingWindowIds.isEmpty })
}

@discardableResult
func saveRestartEnvelope(_ envelope: PersistedFrozenWorldEnvelope, to url: URL) throws -> Bool {
    try prepareRestartStateDirectory(url)
    let previous = try? Data(contentsOf: url)
    let decoded = previous.flatMap { try? JSONDecoder().decode(PersistedFrozenWorldEnvelope.self, from: $0) }
    guard decoded != envelope else { return false }
    let data = try JSONEncoder.winMuxDefault.encode(envelope)
    if let previous, let decoded,
       (1...persistedFrozenWorldVersion).contains(decoded.version) {
        try writePrivateData(previous, to: url.appendingPathExtension("backup"))
    }
    try writePrivateData(data, to: url)
    return true
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
    guard runtime.workspaceBackend.capabilities.usesVirtualRecovery else { return }
    guard !isUnitTest, isWinMuxRuntimeReady, !serverArgs.isReadOnly,
          TrayMenuModel.shared.isEnabled,
          NSWorkspace.shared.frontmostApplication?.bundleIdentifier != lockScreenAppBundleId else { return }
    // Capture current titles without adding AX round trips to every focus/layout event.
    guard recovery.pendingRestartSave == nil else { return }
    recovery.pendingRestartSave = runtime.task {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        if Date.now.timeIntervalSince(recovery.lastRestartIdentityRefresh) >= 5 {
            recovery.lastRestartIdentityRefresh = .now
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
            recovery.pendingRestartSave = nil
            return
        }
        recovery.pendingRestartSave = nil
        do {
            let url = try persistedFrozenWorldUrl()
            recovery.restartWriter.submit(makeRestartEnvelope(), to: url)
        } catch {
            NSLog("WinMuxX: unable to schedule workspace state save: %@", error.localizedDescription)
        }
    }
}

@discardableResult
@MainActor
func loadPersistedFrozenWorldForStartupIfPresent() -> Bool {
    guard runtime.workspaceBackend.capabilities.usesVirtualRecovery else { return false }
    guard !serverArgs.isReadOnly, config.automaticallyTileNewWindows else { return false }
    do {
        let url = try persistedFrozenWorldUrl()
        try prepareRestartStateDirectory(url)
        if let envelope = loadRestartEnvelope(from: url) {
            preparePersistedFrozenWorldForStartup(envelope)
            return true
        }
    } catch { NSLog("WinMuxX: unable to load workspace state: %@", error.localizedDescription) }
    return false
}

@MainActor
func preparePersistedFrozenWorldForStartup(_ envelope: PersistedFrozenWorldEnvelope) {
    recovery.firstUserWorkspaceSelectionDate = nil
    recovery.lateRestartTreeExpiry?.cancel()
    recovery.lateRestartTreeDeadline = .now.addingTimeInterval(30)
    if !isUnitTest {
        recovery.lateRestartTreeExpiry = runtime.task {
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            recovery.lateRestartTreeDeadline = nil
            recovery.restartMatchedWindows = recovery.pendingRestartSnapshots.map { _ in [:] }
            recovery.lateRestartTreeExpiry = nil
            compactPendingRestartSnapshots()
        }
    }
    recovery.pendingRestartSnapshots = (envelope.pending ?? []) + [PendingRestartSnapshot(world: envelope.world,
        remainingWindowIds: envelope.world.windowIds)]
    for index in recovery.pendingRestartSnapshots.indices {
        let identifiable = recovery.pendingRestartSnapshots[index].world.workspaces.flatMap { collectFrozenWindows($0).values }
            .filter { $0.restartIdentity != nil }.map(\.id)
        recovery.pendingRestartSnapshots[index].remainingWindowIds.formIntersection(identifiable)
    }
    recovery.pendingRestartSnapshots = discardSupersededRestartAssignments(recovery.pendingRestartSnapshots)
    recovery.restartMatchedWindows = recovery.pendingRestartSnapshots.map { _ in [:] }
    // Create every saved destination before new-window rules or pruning can take its slot.
    for (index, snapshot) in recovery.pendingRestartSnapshots.enumerated() {
        for saved in snapshot.world.workspaces {
            if index < recovery.pendingRestartSnapshots.count - 1,
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
    recovery.pendingRestartSnapshots.contains { snapshot in
        snapshot.world.workspaces.contains { workspace in
            workspace.name == name && !Set(collectFrozenWindows(workspace).keys)
                .intersection(snapshot.remainingWindowIds).isEmpty
        }
    }
}

@MainActor
func discardPendingRestartWindows(forWorkspace name: String) {
    for index in recovery.pendingRestartSnapshots.indices {
        let ids = recovery.pendingRestartSnapshots[index].world.workspaces.filter { $0.name == name }
            .flatMap { collectFrozenWindows($0).keys }
        recovery.pendingRestartSnapshots[index].remainingWindowIds.subtract(ids)
    }
    compactPendingRestartSnapshots()
}

@MainActor
var pendingRestartWindowCount: Int {
    recovery.pendingRestartSnapshots.reduce(0) { $0 + $1.remainingWindowIds.count }
}

@MainActor
func trackPendingRestartWindow(_ window: Window) {
    guard let identity = window.restartIdentity, allowsSavedPlacement(identity) else { return }
    let bundleId = identity.bundleId
    guard
          recovery.pendingRestartSnapshots.contains(where: { snapshot in
              snapshot.world.workspaces.contains { workspace in
                  collectFrozenWindows(workspace).values.contains {
                      snapshot.remainingWindowIds.contains($0.id) && $0.restartIdentity?.bundleId == bundleId
                  }
              }
          }) else { return }
    recovery.restartWindowAttempts[window.windowId] = RestartWindowAttempt(generation: window.bindingGeneration, started: .now)
    guard !isUnitTest, recovery.restartRetryTask == nil else { return }
    recovery.restartRetryTask = runtime.task {
        defer { recovery.restartRetryTask = nil }
        while !recovery.restartWindowAttempts.isEmpty {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            recovery.restartWindowAttempts = recovery.restartWindowAttempts.filter { Date.now.timeIntervalSince($0.value.started) < 30 }
            guard !Task.isCancelled else { return }
            if !recovery.restartWindowAttempts.isEmpty, isWinMuxRuntimeReady, TrayMenuModel.shared.isEnabled,
               NSWorkspace.shared.frontmostApplication?.bundleIdentifier != lockScreenAppBundleId {
                scheduleRefreshSession(.workspaceRestoration)
            }
        }
    }
}

@MainActor
func forgetPendingRestartWindow(_ id: UInt32) {
    recovery.restartWindowAttempts.removeValue(forKey: id)
}

/// Some apps expose an empty/transient title or document while launching. Retry
/// briefly, but stop as soon as placement changes; user/new-window rules win then.
@MainActor
func retryPendingRestartWindows() async throws {
    for id in Array(recovery.restartWindowAttempts.keys) {
        guard var attempt = recovery.restartWindowAttempts[id] else { continue }
        guard let window = Window.get(byId: id), window.bindingGeneration == attempt.generation,
              Date.now.timeIntervalSince(attempt.started) < 30 else {
            forgetPendingRestartWindow(id)
            continue
        }
        guard Date.now.timeIntervalSince(attempt.lastAttempt) >= 1 else { continue }
        attempt.lastAttempt = .now
        recovery.restartWindowAttempts[id] = attempt
        if let macWindow = window as? MacWindow,
           let identity = try? await macWindow.macApp.getRestartWindowIdentity(id) {
            window.restartIdentity = identity
        }
        guard window.bindingGeneration == attempt.generation else {
            forgetPendingRestartWindow(id)
            continue
        }
        if let identity = window.restartIdentity, !allowsSavedPlacement(identity) {
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
    let world = FrozenWorld(workspaces: [FrozenWorkspace(workspace, assignmentFor: window)], monitors: [], windowIds: [window.windowId])
    recovery.pendingRestartSnapshots.append(PendingRestartSnapshot(world: world, remainingWindowIds: [window.windowId]))
    recovery.restartMatchedWindows.append([:])
}

@MainActor
func restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow window: Window) async throws -> Bool {
    recovery.restartRestorationsInFlight += 1
    defer {
        recovery.restartRestorationsInFlight -= 1
        compactPendingRestartSnapshots()
    }
    guard let identity = window.restartIdentity, allowsSavedPlacement(identity) else { return false }
    let generation = window.bindingGeneration
    let candidates = recovery.pendingRestartSnapshots.indices.flatMap { index in
        recovery.pendingRestartSnapshots[index].world.workspaces.flatMap { workspace in
            collectFrozenWindows(workspace).values
                .filter { recovery.pendingRestartSnapshots[index].remainingWindowIds.contains($0.id) }
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
        window.bindingGeneration == generation, allowsSavedPlacement(identity) else { return false }
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
        await restoreFrozenFloatingSize(window, frozen, on: workspace)
    } else if savedWorkspace.macosUnconventionalWindows.contains(where: { $0.id == savedId }) {
        try await restoreFrozenUnconventionalWindow(window, frozen, on: workspace)
    } else {
        window.bind(to: workspace.rootTilingContainer, adaptiveWeight: frozen.weight, index: INDEX_BIND_LAST)
    }
    let canFinishStartupTree = recovery.lateRestartTreeDeadline.map { Date.now < $0 } == true &&
        frozen.restartIdentity?.pid == identity.pid && frozen.restartIdentity?.launchDate == identity.launchDate &&
        identity.launchDate != nil
    if _isStartup == true || canFinishStartupTree { recovery.restartMatchedWindows[index][savedId] = window }
    if _isStartup != true, canFinishStartupTree,
       !savedWorkspace.floatingWindows.contains(where: { $0.id == savedId }),
       !savedWorkspace.macosUnconventionalWindows.contains(where: { $0.id == savedId }) {
        // Responsive apps can be registered before another app exposes all its windows.
        // Rebuild only this destination; never replay display selection or other workspaces.
        let nonTiledIds = Set((savedWorkspace.floatingWindows + savedWorkspace.macosUnconventionalWindows).map(\.id))
        let matched = recovery.restartMatchedWindows[index].filter {
            !nonTiledIds.contains($0.key) && $0.value.parent is TilingContainer &&
                Window.get(byId: $0.value.windowId) === $0.value && $0.value.nodeWorkspace === workspace
        }
        let world = FrozenWorld(workspaces: [savedWorkspace], monitors: [], windowIds: Set(matched.keys))
        _ = try await restoreFrozenWorldIfNeeded(world, newlyDetectedWindow: window,
            matchedWindows: matched, restoreVisibleWorkspaces: false)
    }
    recovery.pendingRestartSnapshots[index].remainingWindowIds.remove(savedId)
    return true // The new-window placement rules must not override this destination.
}

@MainActor
func finalizePersistedFrozenWorldAfterRefresh(aliveWindowIds: Set<UInt32>) async throws {
    // Only rebuild whole trees during startup. Late app launches must not replay old
    // layouts over windows the user has already moved during the current session.
    guard isStartup else { return }
    recovery.restartRestorationsInFlight += 1
    defer { recovery.restartRestorationsInFlight -= 1 }
    for index in recovery.pendingRestartSnapshots.indices {
        let matched = recovery.restartMatchedWindows[index].filter { aliveWindowIds.contains($0.value.windowId) }
        guard let trigger = matched.values.first else { continue }
        let snapshot = recovery.pendingRestartSnapshots[index].world
        let workspaces = index == recovery.pendingRestartSnapshots.count - 1 ? snapshot.workspaces : snapshot.workspaces.filter {
            !Set(collectFrozenWindows($0).keys).isDisjoint(with: Set(matched.keys))
        }
        let world = FrozenWorld(workspaces: workspaces, monitors: snapshot.monitors, windowIds: Set(matched.keys))
        _ = try await restoreFrozenWorldIfNeeded(world, newlyDetectedWindow: trigger,
            matchedWindows: matched, restoreVisibleWorkspaces: index == recovery.pendingRestartSnapshots.count - 1)
    }
    // Retain the matched windows briefly so delayed windows can recover their exact slots.
}

@MainActor
func resetPersistedFrozenWorldForTests() {
    runtime.recovery.reset()
}
