import AppKit
import Common
import Foundation

@MainActor
final class WorkspaceRecoveryState {
    // AX becomes unobservable while the screen is locked. Keep the last world so
    // windows can return to their tree positions when AX becomes available again.
    var closedWindows = FrozenWorld(workspaces: [], monitors: [], windowIds: [])
    var restartSnapshots: [RestartSnapshotState] = []
    var lateRestartTreeDeadline: Date?
    var lateRestartTreeExpiry: Task<Void, Never>?
    var pendingRestartSave: Task<Void, Never>?
    var lastRestartIdentityRefresh: Date = .distantPast
    var restartWindowAttempts: [UInt32: RestartWindowAttempt] = [:]
    var restartRetryTask: Task<Void, Never>?
    var restartRestorationsInFlight = 0
    var firstUserWorkspaceSelectionDate: Date?
    let restartWriter = RestartStateWriter()
    var restartIdentityQueryForTests: (@MainActor (Window) async -> [(UInt32, RestartWindowIdentity)])?

    func reset() {
        pendingRestartSave?.cancel()
        pendingRestartSave = nil
        restartSnapshots = []
        lateRestartTreeExpiry?.cancel()
        lateRestartTreeExpiry = nil
        lateRestartTreeDeadline = nil
        lastRestartIdentityRefresh = .distantPast
        restartWindowAttempts = [:]
        firstUserWorkspaceSelectionDate = nil
        restartIdentityQueryForTests = nil
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
    forgetClosedWindowsCacheVisibility()
    guard _isStartup != true, isWinMuxRuntimeReady || isUnitTest else { return }
    if recovery.firstUserWorkspaceSelectionDate == nil {
        recovery.firstUserWorkspaceSelectionDate = date
    }
}

@MainActor
private func allowsSavedPlacement(_ identity: RestartWindowIdentity) -> Bool {
    // Snapshots from before these prompts became popups must not bind them into a workspace.
    if KnownBundleId(rawValue: identity.bundleId)?.isSystemAuthenticationAgent == true { return false }
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
    for index in recovery.restartSnapshots.indices { recovery.restartSnapshots[index].matchedWindows.removeAll() }
    compactPendingRestartSnapshots()
}

/// Snapshot indices are used across AX awaits. Compact only after all readers
/// have finished, and after the period that needs complete startup trees.
@MainActor
func compactPendingRestartSnapshots() {
    guard recovery.restartRestorationsInFlight == 0, _isStartup != true,
          recovery.lateRestartTreeDeadline == nil else { return }
    let snapshots = discardSupersededRestartAssignments(recovery.restartSnapshots.map(\.snapshot))
    recovery.restartSnapshots = snapshots.filter { !$0.remainingWindowIds.isEmpty && !$0.isExpired() }
        .map { RestartSnapshotState(snapshot: $0) }
}
/// Runtime-only bookkeeping; the persisted snapshot schema remains separate.
struct RestartSnapshotState {
    var snapshot: PendingRestartSnapshot
    var matchedWindows: [UInt32: Window] = [:]
}

struct RestartWindowAttempt {
    let generation: UInt64
    let started: Date
    var lastAttempt: Date = .distantPast
}

/// Windows that never reappear, such as one-off documents, are forgotten after a week.
let restartSnapshotLifetime: TimeInterval = 7 * 24 * 60 * 60

struct PendingRestartSnapshot: Codable, Equatable, Sendable {
    let world: FrozenWorld
    var remainingWindowIds: Set<UInt32>
    let savedAt: Date

    private enum CodingKeys: String, CodingKey { case world, remainingWindowIds, savedAt }

    init(world: FrozenWorld, remainingWindowIds: Set<UInt32>, savedAt: Date = .now) {
        self.world = world
        self.remainingWindowIds = remainingWindowIds
        self.savedAt = savedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        world = try container.decode(FrozenWorld.self, forKey: .world)
        remainingWindowIds = try container.decode(Set<UInt32>.self, forKey: .remainingWindowIds)
        // Older files have no date: their lifetime starts when they are loaded.
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .now
    }

    func isExpired(at date: Date = .now) -> Bool { date.timeIntervalSince(savedAt) > restartSnapshotLifetime }
}

private struct RestartProcessWindowKey: Hashable {
    let bundleId: String
    let pid: Int32
    let launchDate: Date
    let windowId: UInt32
}

@MainActor
func restartProcessIsRunning(_ identity: RestartWindowIdentity) -> Bool {
    guard let launchDate = identity.launchDate,
          let app = NSRunningApplication(processIdentifier: identity.pid) else { return false }
    return app.bundleIdentifier == identity.bundleId && app.launchDate == launchDate
}

private struct RestartContentKey: Hashable {
    let bundleId: String
    let title: String
    let documentURL: String?
    let accessibilityIdentifier: String?
}

/// Snapshots are ordered oldest to newest. A verified process/window identity
/// has only one current placement, regardless of changing terminal titles.
/// A window indistinguishable from one in a newer snapshot is superseded too: matching
/// needs a unique candidate, so relaunched apps would otherwise accumulate dead entries.
/// An entry whose process still runs is kept; its window may only be missing for now.
@MainActor
func discardSupersededRestartAssignments(
    _ snapshots: [PendingRestartSnapshot],
    isRunning: @MainActor (RestartWindowIdentity) -> Bool = restartProcessIsRunning,
) -> [PendingRestartSnapshot] {
    var result = snapshots
    var seen: Set<RestartProcessWindowKey> = []
    var newerContent: Set<RestartContentKey> = []
    for index in result.indices.reversed() {
        var content: Set<RestartContentKey> = []
        for workspace in result[index].world.workspaces {
            for window in collectFrozenWindows(workspace).values {
                guard let identity = window.restartIdentity else { continue }
                let contentKey = RestartContentKey(bundleId: identity.bundleId, title: identity.title,
                    documentURL: identity.documentURL, accessibilityIdentifier: identity.accessibilityIdentifier)
                content.insert(contentKey)
                if newerContent.contains(contentKey), !isRunning(identity) {
                    result[index].remainingWindowIds.remove(window.id)
                    continue
                }
                guard let launchDate = identity.launchDate else { continue }
                let key = RestartProcessWindowKey(bundleId: identity.bundleId, pid: identity.pid,
                    launchDate: launchDate, windowId: window.id)
                if !seen.insert(key).inserted {
                    result[index].remainingWindowIds.remove(window.id)
                }
            }
        }
        newerContent.formUnion(content)
    }
    return result
}

struct PersistedFrozenWorldEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let world: FrozenWorld
    let pending: [PendingRestartSnapshot]?
}

extension PersistedFrozenWorldEnvelope {
    /// An unreadable pending restart snapshot is left out; the current layout still loads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        world = try container.decode(FrozenWorld.self, forKey: .world)
        pending = try container.decodeIfPresent(LossyDecodableArray<PendingRestartSnapshot>.self, forKey: .pending)?.elements
    }
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
    recovery.pendingRestartSave?.cancel()
    recovery.pendingRestartSave = nil
    guard !isUnitTest, isWinMuxRuntimeReady else { return }
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
    let snapshots = discardSupersededRestartAssignments(recovery.restartSnapshots.map(\.snapshot) +
        [PendingRestartSnapshot(world: world, remainingWindowIds: world.windowIds)])
    return PersistedFrozenWorldEnvelope(version: persistedFrozenWorldVersion, world: world,
        pending: snapshots.dropLast().filter { !$0.remainingWindowIds.isEmpty && !$0.isExpired() })
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
    guard !isUnitTest, isWinMuxRuntimeReady,
          TrayMenuModel.shared.isEnabled,
          !isLockScreenApp(NSWorkspace.shared.frontmostApplication) else { return }
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
              !isLockScreenApp(NSWorkspace.shared.frontmostApplication) else {
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
    guard config.automaticallyTileNewWindows else { return false }
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
            expireLateRestartTreeRestoration()
        }
    }
    recovery.restartSnapshots = ((envelope.pending ?? []).filter { !$0.isExpired() } + [PendingRestartSnapshot(world: envelope.world,
        remainingWindowIds: envelope.world.windowIds)]).map { RestartSnapshotState(snapshot: $0) }
    for index in recovery.restartSnapshots.indices {
        let identifiable = recovery.restartSnapshots[index].snapshot.world.workspaces.flatMap { collectFrozenWindows($0).values }
            .filter { $0.restartIdentity != nil }.map(\.id)
        recovery.restartSnapshots[index].snapshot.remainingWindowIds.formIntersection(identifiable)
    }
    recovery.restartSnapshots = discardSupersededRestartAssignments(recovery.restartSnapshots.map(\.snapshot))
        .map { RestartSnapshotState(snapshot: $0) }
    // Create every saved destination before new-window rules or pruning can take its slot.
    for (index, entry) in recovery.restartSnapshots.enumerated() {
        let snapshot = entry.snapshot
        for saved in snapshot.world.workspaces {
            if index < recovery.restartSnapshots.count - 1,
               Set(collectFrozenWindows(saved).keys).isDisjoint(with: snapshot.remainingWindowIds) { continue }
            let workspace = Workspace.get(byName: saved.name)
            workspace.assignProject(saved.projectId)
            workspace.restoreNamingStyle(saved.namingStyle)
            workspace.restoredDisplayIndex = saved.displayIndex
            workspace.preferredMonitorPoint = saved.monitor.preferredPoint(in: monitors)
        }
    }
}

/// Shared expiry transition; tests can exercise it without waiting on a wall clock.
@MainActor
func expireLateRestartTreeRestoration() {
    recovery.lateRestartTreeDeadline = nil
    for index in recovery.restartSnapshots.indices { recovery.restartSnapshots[index].matchedWindows.removeAll() }
    recovery.lateRestartTreeExpiry = nil
    compactPendingRestartSnapshots()
}

@MainActor
func workspaceHasPendingRestartWindows(_ name: String) -> Bool {
    recovery.restartSnapshots.contains { entry in
        let snapshot = entry.snapshot
        return snapshot.world.workspaces.contains { workspace in
            workspace.name == name && !Set(collectFrozenWindows(workspace).keys)
                .intersection(snapshot.remainingWindowIds).isEmpty
        }
    }
}

@MainActor
func discardPendingRestartWindows(forWorkspace name: String) {
    for index in recovery.restartSnapshots.indices {
        let ids = recovery.restartSnapshots[index].snapshot.world.workspaces.filter { $0.name == name }
            .flatMap { collectFrozenWindows($0).keys }
        recovery.restartSnapshots[index].snapshot.remainingWindowIds.subtract(ids)
    }
    compactPendingRestartSnapshots()
}

@MainActor
var pendingRestartWindowCount: Int {
    recovery.restartSnapshots.reduce(0) { $0 + $1.snapshot.remainingWindowIds.count }
}

@MainActor
func trackPendingRestartWindow(_ window: Window) {
    guard let identity = window.restartIdentity, allowsSavedPlacement(identity) else { return }
    let bundleId = identity.bundleId
    guard
          recovery.restartSnapshots.contains(where: { entry in
              let snapshot = entry.snapshot
              return snapshot.world.workspaces.contains { workspace in
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
               !isLockScreenApp(NSWorkspace.shared.frontmostApplication) {
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
    recovery.restartSnapshots.append(RestartSnapshotState(snapshot:
        PendingRestartSnapshot(world: world, remainingWindowIds: [window.windowId])))
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
    let candidates = recovery.restartSnapshots.indices.flatMap { index in
        recovery.restartSnapshots[index].snapshot.world.workspaces.flatMap { workspace in
            collectFrozenWindows(workspace).values
                .filter { recovery.restartSnapshots[index].snapshot.remainingWindowIds.contains($0.id) }
                .map { (snapshotIndex: index, workspace: workspace, window: $0) }
        }
    }
    let saved = candidates.map(\.window)
    guard !saved.isEmpty else { return false }
    let live: [(UInt32, RestartWindowIdentity)]
    if isUnitTest, let query = recovery.restartIdentityQueryForTests {
        live = await query(window)
    } else if let macWindow = window as? MacWindow {
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
    if _isStartup == true || canFinishStartupTree { recovery.restartSnapshots[index].matchedWindows[savedId] = window }
    if _isStartup != true, canFinishStartupTree,
       !savedWorkspace.floatingWindows.contains(where: { $0.id == savedId }),
       !savedWorkspace.macosUnconventionalWindows.contains(where: { $0.id == savedId }) {
        // Responsive apps can be registered before another app exposes all its windows.
        // Rebuild only this destination; never replay display selection or other workspaces.
        let nonTiledIds = Set((savedWorkspace.floatingWindows + savedWorkspace.macosUnconventionalWindows).map(\.id))
        let matched = recovery.restartSnapshots[index].matchedWindows.filter {
            !nonTiledIds.contains($0.key) && $0.value.parent is TilingContainer &&
                Window.get(byId: $0.value.windowId) === $0.value && $0.value.nodeWorkspace === workspace
        }
        let world = FrozenWorld(workspaces: [savedWorkspace], monitors: [], windowIds: Set(matched.keys))
        _ = try await restoreFrozenWorldIfNeeded(world, newlyDetectedWindow: window,
            matchedWindows: matched, restoreVisibleWorkspaces: false)
    }
    recovery.restartSnapshots[index].snapshot.remainingWindowIds.remove(savedId)
    return true // The new-window placement rules must not override this destination.
}

@MainActor
func finalizePersistedFrozenWorldAfterRefresh(aliveWindowIds: Set<UInt32>) async throws {
    // Only rebuild whole trees during startup. Late app launches must not replay old
    // layouts over windows the user has already moved during the current session.
    guard isStartup else { return }
    recovery.restartRestorationsInFlight += 1
    defer { recovery.restartRestorationsInFlight -= 1 }
    for index in recovery.restartSnapshots.indices {
        let matched = recovery.restartSnapshots[index].matchedWindows.filter { aliveWindowIds.contains($0.value.windowId) }
        guard let trigger = matched.values.first else { continue }
        let snapshot = recovery.restartSnapshots[index].snapshot.world
        let workspaces = index == recovery.restartSnapshots.count - 1 ? snapshot.workspaces : snapshot.workspaces.filter {
            !Set(collectFrozenWindows($0).keys).isDisjoint(with: Set(matched.keys))
        }
        let world = FrozenWorld(workspaces: workspaces, monitors: snapshot.monitors, windowIds: Set(matched.keys))
        _ = try await restoreFrozenWorldIfNeeded(world, newlyDetectedWindow: trigger,
            matchedWindows: matched, restoreVisibleWorkspaces: index == recovery.restartSnapshots.count - 1)
    }
    // Retain the matched windows briefly so delayed windows can recover their exact slots.
}

@MainActor
func resetPersistedFrozenWorldForTests() {
    runtime.recovery.reset()
}
