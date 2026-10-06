import Foundation

/// The process launch distinguishes surviving windows from recycled macOS IDs.
/// Across launches, only an unambiguous app + nonempty title match is accepted.
struct RestartWindowIdentity: Codable, Equatable, Sendable {
    let bundleId: String
    let pid: Int32
    let launchDate: Date?
    let title: String
}

func matchRestartWindow(
    id: UInt32,
    identity: RestartWindowIdentity,
    saved: [FrozenWindow],
    live: [(UInt32, RestartWindowIdentity)]
) -> UInt32? {
    let sameProcess = saved.filter {
        $0.id == id && $0.restartIdentity?.bundleId == identity.bundleId &&
            $0.restartIdentity?.pid == identity.pid && identity.launchDate != nil &&
            $0.restartIdentity?.launchDate == identity.launchDate
    }
    if sameProcess.count == 1 { return sameProcess[0].id }
    guard !identity.title.isEmpty else { return nil }
    let candidates = saved.filter {
        $0.restartIdentity?.bundleId == identity.bundleId && $0.restartIdentity?.title == identity.title
    }
    let liveMatches = live.filter { $0.1.bundleId == identity.bundleId && $0.1.title == identity.title }
    guard candidates.count == 1, liveMatches.count == 1 else { return nil }
    return candidates[0].id
}
