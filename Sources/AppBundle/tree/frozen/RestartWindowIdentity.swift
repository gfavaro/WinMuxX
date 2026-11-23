import CoreGraphics
import Foundation

/// IDs are trusted only within a verified process launch. Reopened windows need
/// a unique match using the metadata the application actually exposes.
struct RestartWindowIdentity: Codable, Equatable, Sendable {
    let bundleId: String
    let pid: Int32
    let launchDate: Date?
    let title: String
    let documentURL: String?
    let accessibilityIdentifier: String?
    /// Where the window was last seen. Only breaks ties between windows the other evidence cannot
    /// tell apart; files saved before it existed decode it as nil.
    let frame: CGRect?

    init(bundleId: String, pid: Int32, launchDate: Date?, title: String,
         documentURL: String? = nil, accessibilityIdentifier: String? = nil, frame: CGRect? = nil) {
        self.bundleId = bundleId
        self.pid = pid
        self.launchDate = launchDate
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.documentURL = Self.nonempty(documentURL)
        self.accessibilityIdentifier = Self.nonempty(accessibilityIdentifier)
        self.frame = frame
    }

    /// Apps restore saved frames with small adjustments (title bars, rounding).
    static let frameTolerance: CGFloat = 8

    func frameIsNear(_ other: CGRect) -> Bool {
        guard let frame else { return false }
        return abs(frame.minX - other.minX) <= Self.frameTolerance && abs(frame.minY - other.minY) <= Self.frameTolerance &&
            abs(frame.width - other.width) <= Self.frameTolerance && abs(frame.height - other.height) <= Self.frameTolerance
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Strong evidence outweighs a title, but contradictory evidence rejects a
    /// match. Generic AX identifiers still need uniqueness across saved/live windows.
    func matchStrength(with other: Self) -> Int {
        guard bundleId == other.bundleId else { return 0 }
        var strength = 0
        if let documentURL, let otherDocument = other.documentURL {
            guard documentURL == otherDocument else { return 0 }
            strength += 4
        }
        if let accessibilityIdentifier, let otherIdentifier = other.accessibilityIdentifier {
            guard accessibilityIdentifier == otherIdentifier else { return 0 }
            strength += 2
        }
        if !title.isEmpty && title == other.title { strength += 1 }
        return strength
    }

    func contradicts(_ other: Self) -> Bool {
        if let documentURL, let otherDocument = other.documentURL, documentURL != otherDocument { return true }
        if let accessibilityIdentifier, let otherIdentifier = other.accessibilityIdentifier,
           accessibilityIdentifier != otherIdentifier { return true }
        return false
    }
}

/// Return the candidate's position, not its old macOS ID: IDs can collide between
/// pending snapshots from different sessions.
func matchRestartWindowIndex(
    id: UInt32,
    identity: RestartWindowIdentity,
    saved: [FrozenWindow],
    live: [(UInt32, RestartWindowIdentity)],
    claimed: Set<UInt32> = []
) -> Int? {
    let sameProcess = saved.indices.filter {
        saved[$0].id == id && saved[$0].restartIdentity?.bundleId == identity.bundleId &&
            saved[$0].restartIdentity?.pid == identity.pid && identity.launchDate != nil &&
            saved[$0].restartIdentity?.launchDate == identity.launchDate
    }
    if sameProcess.count == 1 { return sameProcess[0] }
    let strengths = saved.map { $0.restartIdentity?.matchStrength(with: identity) ?? 0 }
    guard let strongest = strengths.max(), strongest > 0 else {
        return soleRelaunchedWindowIndex(id: id, identity: identity, saved: saved, live: live, claimed: claimed) ??
            tiedRelaunchedWindowIndex(id: id, identity: identity, saved: saved, live: live, claimed: claimed,
                tied: saved.indices.filter { saved[$0].restartIdentity?.bundleId == identity.bundleId })
    }
    let candidates = saved.indices.filter { strengths[$0] == strongest }
    if candidates.count > 1 {
        return tiedRelaunchedWindowIndex(id: id, identity: identity, saved: saved, live: live, claimed: claimed, tied: candidates)
    }
    guard let index = candidates.first, let selected = saved[index].restartIdentity else { return nil }
    let competingLiveWindows = live.filter { !claimed.contains($0.0) && selected.matchStrength(with: $0.1) >= strongest }
    guard competingLiveWindows.count == 1, competingLiveWindows[0].0 == id else { return nil }
    return index
}

/// Titles such as a chat or web page change between launches. When a relaunched app
/// has exactly one saved and one live window, they are the same window.
private func soleRelaunchedWindowIndex(
    id: UInt32,
    identity: RestartWindowIdentity,
    saved: [FrozenWindow],
    live: [(UInt32, RestartWindowIdentity)],
    claimed: Set<UInt32>
) -> Int? {
    let sameApp = saved.indices.filter { saved[$0].restartIdentity?.bundleId == identity.bundleId }
    guard sameApp.count == 1, let index = sameApp.first, let selected = saved[index].restartIdentity,
          identity.launchDate != nil, selected.launchDate != identity.launchDate,
          !selected.contradicts(identity) else { return nil }
    let liveWindows = live.filter { $0.1.bundleId == identity.bundleId && !claimed.contains($0.0) }
    guard liveWindows.count == 1, liveWindows[0].0 == id else { return nil }
    return index
}

/// Several saved windows of a relaunched app that the other evidence cannot tell apart, and as
/// many live ones still unclaimed. A saved frame near this window's frame decides when it is
/// unambiguous both ways; otherwise the windows pair in creation order (window ids ascend).
private func tiedRelaunchedWindowIndex(
    id: UInt32,
    identity: RestartWindowIdentity,
    saved: [FrozenWindow],
    live: [(UInt32, RestartWindowIdentity)],
    claimed: Set<UInt32>,
    tied: [Int]
) -> Int? {
    guard tied.count > 1, identity.launchDate != nil,
          tied.allSatisfy({ index in
              saved[index].restartIdentity.map { $0.launchDate != identity.launchDate && !$0.contradicts(identity) } == true
          }) else { return nil }
    let unclaimed = live.filter { $0.1.bundleId == identity.bundleId && !claimed.contains($0.0) }.sorted { $0.0 < $1.0 }
    guard unclaimed.count == tied.count, let rank = unclaimed.firstIndex(where: { $0.0 == id }) else { return nil }
    if let frame = identity.frame {
        let near = tied.filter { saved[$0].restartIdentity?.frameIsNear(frame) == true }
        if near.count == 1, let savedFrame = saved[near[0]].restartIdentity?.frame,
           unclaimed.filter({ candidate in candidate.1.frameIsNear(savedFrame) }).count == 1 {
            return near[0]
        }
    }
    return tied.sorted { saved[$0].id < saved[$1].id }[rank]
}
