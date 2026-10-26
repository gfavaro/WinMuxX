import Foundation

/// macOS owns membership and visibility. These records are observations, never
/// instructions to create, delete, activate, relocate or park a workspace.
public struct NativeWorkspaceRecord: Equatable, Sendable {
    public let displayIdentifier: String
    public let space: NativeSpace
    public let isActive: Bool

    /// Numeric IDs and presentation ordinals must never key restart recovery.
    /// A missing UUID leaves the Space observable, but ineligible for restoration.
    public var persistenceKey: String? { space.uuid.map { "native:\($0)" } }
}

/// A generation belongs to one inventory owner; tokens cannot cross runtimes.
public struct NativeSpacesReadToken: Equatable, Sendable {
    fileprivate let owner: UUID
    fileprivate let generation: UInt64
}

/// Separates retained diagnostic data from a current, trusted observation.
/// Invalidating immediately revokes eligibility, before an asynchronous read starts.
public struct NativeWorkspaceInventory: Sendable {
    public enum Status: Equatable, Sendable {
        case stopped
        case reading
        case available
        case unavailable(String)
    }

    private let owner = UUID()
    private var generation: UInt64 = 0
    public private(set) var status: Status = .stopped
    public private(set) var lastSnapshot: NativeSpacesSnapshot?
    public private(set) var records: [NativeWorkspaceRecord] = []
    public var currentSnapshot: NativeSpacesSnapshot? {
        status == .available ? lastSnapshot : nil
    }

    public init() {}

    @discardableResult
    public mutating func invalidate() -> NativeSpacesReadToken {
        generation &+= 1
        status = .reading
        return NativeSpacesReadToken(owner: owner, generation: generation)
    }

    /// A rejected or superseded read leaves layout ownership suspended. Retained
    /// records may be shown as stale diagnostics, but cannot authorize frame writes.
    @discardableResult
    public mutating func publish(_ snapshot: NativeSpacesSnapshot, for token: NativeSpacesReadToken) -> Bool {
        guard accepts(token) else { return false }
        var uuids = Set<String>()
        var ids = Set<String>()
        var next: [NativeWorkspaceRecord] = []
        for display in snapshot.displays {
            for space in display.spaces {
                // Shared desktop IDs can occur when "Displays have separate Spaces"
                // is disabled. Observe the snapshot but do not invent two owners.
                let owners = snapshot.displays.filter { $0.spaces.contains { $0.id == space.id } }
                guard owners.count == 1 else { continue }
                guard ids.insert(space.id).inserted,
                      space.uuid.map({ uuids.insert($0).inserted }) ?? true else {
                    status = .unavailable("duplicate native Space identity")
                    return false
                }
                next.append(NativeWorkspaceRecord(displayIdentifier: display.identifier, space: space,
                    isActive: display.activeSpaceID == space.id))
            }
        }
        lastSnapshot = snapshot
        records = next
        status = .available
        return true
    }

    public mutating func fail(_ reason: String, for token: NativeSpacesReadToken) {
        guard accepts(token) else { return }
        status = .unavailable(reason)
    }

    public mutating func stop() {
        generation &+= 1
        status = .stopped
    }

    private func accepts(_ token: NativeSpacesReadToken) -> Bool {
        token.owner == owner && token.generation == generation && status == .reading
    }
}
