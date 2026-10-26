import AppKit
import Common
import NativeSpaces

/// Read-only adoption into the existing layout tree. WindowServer supplies
/// membership, CG supplies process ownership, AX supplies window classification.
/// Failure/absence from AX is never a window-closure signal.
@MainActor
final class NativeWindowReconciler {
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private(set) var lastDurationMilliseconds: Double?
    private(set) var lastError: String?
    private(set) var pendingWindowCount = 0
    private(set) var writePreflight: (passed: Int, blocked: Int)?
    private(set) var timedOutAppCount = 0

    func invalidate() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    func reconcile(_ snapshot: NativeSpacesSnapshot) {
        invalidate()
        guard AXIsProcessTrusted(), !isUnitTest else { return }
        let version = generation
        let owner = runtime
        task = owner.task { [weak self, weak owner] in
            guard let self, let owner else { return }
            let started = ContinuousClock.now
            do {
                let eligible = Set(snapshot.windows.compactMap { membership in
                    owner.workspaceBackend.nativeLayouts.registrationWorkspace(for: membership.windowID) == nil ? nil : membership.windowID
                })
                let pids = await Task.detached { nativeWindowOwnerPIDs(eligible) }.value
                try Task.checkCancellation()
                guard self.generation == version else { return }
                Self.updateEligibility(snapshot, windows: MacWindow.allWindows, ownerPIDs: pids,
                    layouts: owner.workspaceBackend.nativeLayouts)
                for app in Array(MacApp.allAppsMap.values) where app.nsApp.isTerminated {
                    try Task.checkCancellation()
                    await app.destroy()
                }
                let groups = Dictionary(grouping: pids.keys, by: { pids[$0]! })
                self.timedOutAppCount = 0
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (pid, ids) in groups {
                        group.addTask { @Sendable @MainActor in
                            let work = owner.throwingTask {
                                guard let running = NSRunningApplication(processIdentifier: pid),
                                      running.activationPolicy == .regular, !running.isTerminated,
                                      let app = try await MacApp.getOrRegister(running) else { return }
                                for id in ids.sorted() {
                                    try Task.checkCancellation()
                                    guard self.generation == version else { throw CancellationError() }
                                    let window = try? await MacWindow.getOrRegister(windowId: id, macApp: app)
                                    window?.nativeLayoutEligible = window != nil
                                }
                            }
                            // Match the existing app refresh's cooperative budget.
                            // An AX call already dispatched still has to answer or
                            // hit its 1s messaging timeout; other apps keep running.
                            let deadline = Task { @MainActor in
                                do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
                                work.cancel()
                            }
                            defer { deadline.cancel() }
                            try await withTaskCancellationHandler {
                                do { try await work.value }
                                catch is CancellationError {
                                    try Task.checkCancellation()
                                    if self.generation == version { self.timedOutAppCount += 1 }
                                }
                            } onCancel: { work.cancel() }
                        }
                    }
                    try await group.waitForAll()
                }
                guard self.generation == version else { return }
                // Absence from AX, membership inventory or a failed bounds query
                // never proves closure. Individual closure comes from the native
                // close event; process death is independently confirmed here.
                for window in MacWindow.allWindows where window.macApp.nsApp.isTerminated {
                    window.garbageCollect(skipClosedWindowsCache: true)
                }
                self.pendingWindowCount = eligible.filter { MacWindow.allWindowsMap[$0] == nil }.count
                let identities = MacWindow.allWindows.compactMap { window -> NativeWindowWriteIdentity? in
                    guard window.nativeLayoutEligible, eligible.contains(window.windowId), let launched = window.macApp.nsApp.launchDate,
                          owner.workspaceBackend.nativeLayouts.registrationWorkspace(for: window.windowId) === window.nodeWorkspace else { return nil }
                    for display in snapshot.displays {
                        if case .desktop(let spaceID, let uuid?) = snapshot.eligibility(windowID: window.windowId, on: display.identifier) {
                            return NativeWindowWriteIdentity(windowID: window.windowId, pid: window.macApp.pid,
                                processLaunchDate: launched, displayIdentifier: display.identifier, spaceID: spaceID, spaceUUID: uuid)
                        }
                    }
                    return nil
                }
                // A local, read-only probe. Never populate the runtime's write
                // authority: observation mode remains physically read-only.
                let preflight = Task.detached {
                    let authority = NativeSpaceWriteAuthority()
                    authority.replace(snapshot: snapshot, identities: identities)
                    var passed: [UInt32] = []
                    for identity in identities {
                        if Task.isCancelled { break }
                        if let permit = authority.permit(windowID: identity.windowID, pid: identity.pid,
                            processLaunchDate: identity.processLaunchDate), (try? permit.check()) != nil { passed.append(identity.windowID) }
                    }
                    return (passed, identities.count - passed.count)
                }
                let result = await withTaskCancellationHandler { await preflight.value } onCancel: { preflight.cancel() }
                guard self.generation == version else { return }
                self.writePreflight = (result.0.count, result.1)
                owner.workspaceBackend.observation?.watchManagedWindows(Set(MacWindow.allWindowsMap.keys))
                await owner.workspaceBackend.nativeTiling.accept(snapshot, identities: identities.filter { result.0.contains($0.windowID) })
                self.lastError = nil
            } catch is CancellationError { return }
            catch { if self.generation == version { self.lastError = String(describing: error) } }
            guard self.generation == version else { return }
            let duration = started.duration(to: .now).components
            self.lastDurationMilliseconds = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            self.task = nil
        }
    }

    static func updateEligibility(_ snapshot: NativeSpacesSnapshot, windows: [Window],
                                  ownerPIDs: [UInt32: Int32], layouts: NativeSpaceLayouts) {
        let queried = Set(snapshot.reconciliationSpaceIDs ?? snapshot.displays.map(\.activeSpaceID))
        for window in windows {
            let owners = snapshot.displays.filter {
                layouts.activeWorkspace(on: $0.identifier) === window.nodeWorkspace
            }
            guard !owners.isEmpty else { window.nativeLayoutEligible = false; continue }
            // Incoming-Space reads deliberately omit the unchanged displays'
            // memberships. Retain their presentation, but never fabricate fresh
            // write authority from that retained state.
            guard owners.contains(where: { queried.contains($0.activeSpaceID) }) else { continue }
            window.nativeLayoutEligible = ownerPIDs[window.windowId] == window.app.pid &&
                layouts.registrationWorkspace(for: window.windowId) === window.nodeWorkspace
        }
    }
}

private func nativeWindowOwnerPIDs(_ ids: Set<UInt32>) -> [UInt32: Int32] {
    guard let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return [:] }
    var result: [UInt32: Int32] = [:]
    for row in rows {
        guard let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value, ids.contains(id),
              (row[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
              let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              pid > 0, pid != getpid() else { continue }
        result[id] = pid
    }
    return result
}
