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

    init(bundleId: String, pid: Int32, launchDate: Date?, title: String,
         documentURL: String? = nil, accessibilityIdentifier: String? = nil) {
        self.bundleId = bundleId
        self.pid = pid
        self.launchDate = launchDate
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.documentURL = Self.nonempty(documentURL)
        self.accessibilityIdentifier = Self.nonempty(accessibilityIdentifier)
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
    live: [(UInt32, RestartWindowIdentity)]
) -> Int? {
    let sameProcess = saved.indices.filter {
        saved[$0].id == id && saved[$0].restartIdentity?.bundleId == identity.bundleId &&
            saved[$0].restartIdentity?.pid == identity.pid && identity.launchDate != nil &&
            saved[$0].restartIdentity?.launchDate == identity.launchDate
    }
    if sameProcess.count == 1 { return sameProcess[0] }
    let strengths = saved.map { $0.restartIdentity?.matchStrength(with: identity) ?? 0 }
    guard let strongest = strengths.max(), strongest > 0 else {
        return soleRelaunchedWindowIndex(id: id, identity: identity, saved: saved, live: live)
    }
    let candidates = saved.indices.filter { strengths[$0] == strongest }
    guard candidates.count == 1, let index = candidates.first,
          let selected = saved[index].restartIdentity else { return nil }
    let competingLiveWindows = live.filter { selected.matchStrength(with: $0.1) >= strongest }
    guard competingLiveWindows.count == 1, competingLiveWindows[0].0 == id else { return nil }
    return index
}

/// Titles such as a chat or web page change between launches. When a relaunched app
/// has exactly one saved and one live window, they are the same window.
private func soleRelaunchedWindowIndex(
    id: UInt32,
    identity: RestartWindowIdentity,
    saved: [FrozenWindow],
    live: [(UInt32, RestartWindowIdentity)]
) -> Int? {
    let sameApp = saved.indices.filter { saved[$0].restartIdentity?.bundleId == identity.bundleId }
    guard sameApp.count == 1, let index = sameApp.first, let selected = saved[index].restartIdentity,
          identity.launchDate != nil, selected.launchDate != identity.launchDate,
          !selected.contradicts(identity) else { return nil }
    let liveWindows = live.filter { $0.1.bundleId == identity.bundleId }
    guard liveWindows.count == 1, liveWindows[0].0 == id else { return nil }
    return index
}
