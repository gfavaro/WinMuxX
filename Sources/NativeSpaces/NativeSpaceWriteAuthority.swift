import AppKit
import CoreGraphics
import Foundation

public struct NativeWindowWriteIdentity: Equatable, Sendable {
    public let windowID: UInt32
    public let pid: Int32
    public let processLaunchDate: Date
    public let displayIdentifier: String
    public let spaceID: String
    public let spaceUUID: String

    public init(windowID: UInt32, pid: Int32, processLaunchDate: Date, displayIdentifier: String,
                spaceID: String, spaceUUID: String) {
        self.windowID = windowID
        self.pid = pid
        self.processLaunchDate = processLaunchDate
        self.displayIdentifier = displayIdentifier
        self.spaceID = spaceID
        self.spaceUUID = spaceUUID
    }
}

public enum NativeSpaceWriteError: Error, Equatable {
    case revoked
    case liveOwnershipChanged
}

/// An immutable per-job permit. Checking it performs fresh read-side IPC on the
/// calling app's AX thread; it never activates, moves Spaces or writes a window.
public struct NativeSpaceWritePermit: Sendable {
    private let authority: NativeSpaceWriteAuthority
    private let generation: UInt64
    private let identity: NativeWindowWriteIdentity

    fileprivate init(authority: NativeSpaceWriteAuthority, generation: UInt64, identity: NativeWindowWriteIdentity) {
        self.authority = authority
        self.generation = generation
        self.identity = identity
    }

    public func check() throws {
        try authority.check(generation: generation, identity: identity)
    }

    /// Only whether the authority still grants this permit: no live IPC. For repeated
    /// writes after a full check, such as a pan's streamed steps.
    public func checkGranted() throws {
        guard authority.grants(generation: generation, identity: identity) else { throw NativeSpaceWriteError.revoked }
    }
}

/// Explicit focus generates its own app-activation notifications. Those invalidate
/// frame batches, but must not interrupt the focus operation halfway through.
/// This short-lived lease rechecks actual ownership at each focus step instead.
/// Callers must also cancel the AX job on a newer explicit focus or mouse click.
public struct NativeSpaceFocusLease: Sendable {
    private let identity: NativeWindowWriteIdentity
    private let validateLive: @Sendable (NativeWindowWriteIdentity) throws -> Bool
    private let deadline: ContinuousClock.Instant

    init(identity: NativeWindowWriteIdentity, validateLive: @escaping @Sendable (NativeWindowWriteIdentity) throws -> Bool,
         lifetime: Duration = .seconds(2)) {
        self.identity = identity
        self.validateLive = validateLive
        deadline = .now.advanced(by: lifetime)
    }

    public func check() throws {
        guard ContinuousClock.now < deadline else { throw NativeSpaceWriteError.revoked }
        guard try validateLive(identity) else { throw NativeSpaceWriteError.liveOwnershipChanged }
        guard ContinuousClock.now < deadline else { throw NativeSpaceWriteError.revoked }
    }
}

/// Lock-protected invalidation is synchronous and performs no IPC. A queued AX
/// job must check its permit before every frame write, retry or animation step.
/// This is not an atomic WindowServer+AX transaction: already-dispatched AX calls
/// cannot be recalled. Checks bracket live reads and bound that unavoidable race.
public final class NativeSpaceWriteAuthority: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var allowed: [UInt32: NativeWindowWriteIdentity] = [:]
    private let validateLive: @Sendable (NativeWindowWriteIdentity) throws -> Bool
    /// A passed live check, reused briefly within the same generation: a layout's
    /// back-to-back writes otherwise repeat the full WindowServer read per attribute.
    /// Any invalidation starts a new generation, which discards the reuse at once.
    private var liveValidated: [UInt32: (generation: UInt64, at: ContinuousClock.Instant)] = [:]
    var liveValidationReuse: Duration = .milliseconds(100)

    public convenience init() { self.init(validateLive: Self.validateLive) }

    init(validateLive: @escaping @Sendable (NativeWindowWriteIdentity) throws -> Bool) {
        self.validateLive = validateLive
    }

    public func invalidate() {
        lock.withLock {
            generation &+= 1
            allowed = [:]
            liveValidated = [:]
        }
    }

    /// Install only identities backed by this observation's unambiguous active
    /// desktop membership. Missing UUIDs, inactive/shared/fullscreen windows fail.
    public func replace(snapshot: NativeSpacesSnapshot, identities: [NativeWindowWriteIdentity]) {
        var next: [UInt32: NativeWindowWriteIdentity] = [:]
        var seen = Set<UInt32>(), duplicated = Set<UInt32>()
        for identity in identities {
            guard seen.insert(identity.windowID).inserted else {
                duplicated.insert(identity.windowID)
                next[identity.windowID] = nil
                continue
            }
            guard identity.pid > 0, identity.windowID != 0,
                  case .desktop(let id, let uuid) = snapshot.eligibility(windowID: identity.windowID, on: identity.displayIdentifier),
                  id == identity.spaceID, uuid == identity.spaceUUID, !identity.spaceUUID.isEmpty else { continue }
            next[identity.windowID] = identity
        }
        for id in duplicated { next[id] = nil }
        lock.withLock {
            generation &+= 1
            allowed = next
            liveValidated = [:]
        }
    }

    public func permit(windowID: UInt32, pid: Int32, processLaunchDate: Date) -> NativeSpaceWritePermit? {
        lock.withLock {
            guard let identity = allowed[windowID], identity.pid == pid,
                  identity.processLaunchDate == processLaunchDate else { return nil }
            return NativeSpaceWritePermit(authority: self, generation: generation, identity: identity)
        }
    }

    public func explicitFocusLease(windowID: UInt32, pid: Int32, processLaunchDate: Date) -> NativeSpaceFocusLease? {
        lock.withLock {
            guard let identity = allowed[windowID], identity.pid == pid,
                  identity.processLaunchDate == processLaunchDate else { return nil }
            return NativeSpaceFocusLease(identity: identity, validateLive: validateLive)
        }
    }

    fileprivate func grants(generation: UInt64, identity: NativeWindowWriteIdentity) -> Bool {
        lock.withLock { self.generation == generation && allowed[identity.windowID] == identity }
    }

    fileprivate func check(generation: UInt64, identity: NativeWindowWriteIdentity) throws {
        func current() -> Bool { lock.withLock { self.generation == generation && allowed[identity.windowID] == identity } }
        guard current() else { throw NativeSpaceWriteError.revoked }
        let reusable = lock.withLock {
            liveValidated[identity.windowID].map { $0.generation == generation && $0.at.duration(to: .now) < liveValidationReuse } ?? false
        }
        if reusable { return }
        guard try validateLive(identity) else { throw NativeSpaceWriteError.liveOwnershipChanged }
        guard current() else { throw NativeSpaceWriteError.revoked }
        lock.withLock { liveValidated[identity.windowID] = (generation, .now) }
    }

    private static func validateLive(_ identity: NativeWindowWriteIdentity) throws -> Bool {
        let bridge = try SkyLightReadOnlyBridge()
        let before = try NativeSpacesSnapshot.parseDisplays(bridge.copyDisplays())
        let membership = bridge.spaces(for: identity.windowID)
        let after = try NativeSpacesSnapshot.parseDisplays(bridge.copyDisplays())
        guard before == after else { return false }
        let snapshot = NativeSpacesSnapshot(displays: after,
            windows: [NativeWindowMembership(windowID: identity.windowID, spaceIDs: membership)],
            readMilliseconds: 0, capturedAt: .now)
        guard case .desktop(let id, let uuid) = snapshot.eligibility(windowID: identity.windowID, on: identity.displayIdentifier),
              id == identity.spaceID, uuid == identity.spaceUUID,
              let running = NSRunningApplication(processIdentifier: identity.pid),
              !running.isHidden, !running.isTerminated, running.launchDate == identity.processLaunchDate,
              let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              NativeSpaceTransitionGuard.allowsFrameOperations(windows: rows),
              let row = rows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == identity.windowID }),
              (row[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
              (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == identity.pid else { return false }
        return true
    }
}
