import CoreGraphics
import Darwin
import Foundation

/// The read-side private API boundary. No activation, move, add/remove, tag mutation,
/// scripting addition or symbol-table scanning is exposed. Explicit Space navigation
/// is the only synthesized input, isolated in NativeDockSwipe.
/// Calls are serialized by NativeSpacesReader, away from the main actor.
protocol NativeSpacesQuerying {
    func copyDisplays() throws -> [[String: Any]]
    func spaces(for id: UInt32) -> [String]?
    func windowIDs(inSpace id: UInt64) -> [UInt32]?
}

extension NativeSpacesQuerying {
    func windowIDs(inSpace id: UInt64) -> [UInt32]? { nil }
}

final class SkyLightReadOnlyBridge: NativeSpacesQuerying {
    private typealias Connection = @convention(c) () -> Int32
    private typealias Displays = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias Membership = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SpaceWindows = @convention(c) (Int32, Int32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>?
    private let connection: Connection
    private let displays: Displays
    private let membership: Membership
    private let spaceWindows: SpaceWindows?

    private final class Library: @unchecked Sendable {
        static let shared = Library()
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    }

    init() throws {
        guard let handle = Library.shared.handle else {
            throw NativeSpacesError.unavailable("SkyLight cannot be loaded")
        }
        // The process-lifetime handle owns these function pointers. Never dlclose it
        // while a reader, pending read, or future reader can use the symbols.
        func symbol(_ sls: String, _ cgs: String) throws -> UnsafeMutableRawPointer {
            guard let address = dlsym(handle, sls) ?? dlsym(handle, cgs) else {
                throw NativeSpacesError.unavailable("missing \(sls)/\(cgs)")
            }
            return address
        }
        connection = unsafeBitCast(try symbol("SLSMainConnectionID", "CGSMainConnectionID"), to: Connection.self)
        displays = unsafeBitCast(try symbol("SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"), to: Displays.self)
        membership = unsafeBitCast(try symbol("SLSCopySpacesForWindows", "CGSCopySpacesForWindows"), to: Membership.self)
        spaceWindows = (dlsym(handle, "SLSCopyWindowsWithOptionsAndTags") ?? dlsym(handle, "CGSCopyWindowsWithOptionsAndTags"))
            .map { unsafeBitCast($0, to: SpaceWindows.self) }
    }

    func copyDisplays() throws -> [[String: Any]] {
        guard let array = displays(connection())?.takeRetainedValue(),
              let result = array as? [[String: Any]] else {
            throw NativeSpacesError.unavailable("managed display query returned no valid array")
        }
        return result
    }

    func spaces(for id: UInt32) -> [String]? {
        let ids = [NSNumber(value: id)] as CFArray
        guard let array = membership(connection(), 0x7, ids)?.takeRetainedValue(),
              let numbers = array as? [NSNumber],
              numbers.allSatisfy({ CFGetTypeID($0) != CFBooleanGetTypeID() && UInt64($0.stringValue) != nil && $0.uint64Value != 0 }) else { return nil }
        return Array(Set(numbers.map { String($0.uint64Value) })).sorted()
    }

    func windowIDs(inSpace id: UInt64) -> [UInt32]? {
        guard let spaceWindows else { return nil }
        var setTags: UInt64 = 0, clearTags: UInt64 = 0
        // Dinky query.m / yabai: 0x7 includes minimized candidates. This returns
        // candidates only; membership and AX classification remain mandatory.
        guard let values = spaceWindows(connection(), 0, [NSNumber(value: id)] as CFArray,
            0x7, &setTags, &clearTags)?.takeRetainedValue() as? [NSNumber],
              values.allSatisfy({ CFGetTypeID($0) != CFBooleanGetTypeID() && UInt32($0.stringValue).map { $0 != 0 } == true }) else { return nil }
        return Array(Set(values.map(\.uint32Value))).sorted()
    }
}

public actor NativeSpacesReader {
    private var bridge: (any NativeSpacesQuerying)?
    private let makeBridge: @Sendable () throws -> any NativeSpacesQuerying

    public init() { makeBridge = { try SkyLightReadOnlyBridge() } }

    init(makeBridge: @escaping @Sendable () throws -> any NativeSpacesQuerying) {
        self.makeBridge = makeBridge
    }

    /// Cheap topology audit: no CG window inventory or per-window membership IPC.
    public func topology() throws -> [NativeSpaceDisplay] {
        try Task.checkCancellation()
        if bridge == nil { bridge = try makeBridge() }
        guard let bridge else { throw NativeSpacesError.unavailable("bridge initialization failed") }
        return try NativeSpacesSnapshot.parseDisplays(bridge.copyDisplays())
    }

    public func observationSnapshot(previous: [NativeSpaceDisplay]?, allCurrentSpaces: Bool = false) throws -> NativeSpacesSnapshot {
        let current = try topology()
        let targets = allCurrentSpaces ? Set(current.map(\.activeSpaceID))
            : NativeSpacesReconciliation.targets(previous: previous, current: current)
        var value: NativeSpacesSnapshot
        do { value = try snapshot(spaceIDs: targets) }
        catch NativeSpacesError.unavailable {
            // Optional scoped query may be absent on an OS release. The public
            // diagnostic inventory is safe; it never grants cross-Space ownership.
            value = try snapshot()
        }
        guard value.displays == current else { throw NativeSpacesError.invalidSnapshot("topology changed before scoped read") }
        value.reconciliationSpaceIDs = targets.sorted()
        return value
    }

    public func snapshot(windowIDs: [UInt32]? = nil, spaceIDs: Set<String>? = nil) throws -> NativeSpacesSnapshot {
        let start = ContinuousClock.now
        try Task.checkCancellation()
        if bridge == nil { bridge = try makeBridge() }
        guard let bridge else { throw NativeSpacesError.unavailable("bridge initialization failed") }
        let topology = try NativeSpacesSnapshot.parseDisplays(bridge.copyDisplays())
        let ids: [UInt32]
        guard windowIDs == nil || spaceIDs == nil else { throw NativeSpacesError.invalidSnapshot("choose window IDs or Space IDs") }
        if let spaceIDs {
            let known = Set(topology.flatMap(\.spaces).map(\.id))
            guard spaceIDs.isSubset(of: known) else { throw NativeSpacesError.invalidSnapshot("requested Space no longer exists") }
            var candidates = Set<UInt32>()
            for id in spaceIDs.sorted() {
                guard let nativeID = UInt64(id), let found = bridge.windowIDs(inSpace: nativeID) else {
                    throw NativeSpacesError.unavailable("Space-scoped window query unavailable")
                }
                candidates.formUnion(found)
                guard candidates.count <= 1024 else { throw NativeSpacesError.invalidSnapshot("Space inventory exceeds read budget") }
            }
            ids = candidates.sorted()
        } else if let windowIDs {
            guard windowIDs.count <= 1024, windowIDs.allSatisfy({ $0 != 0 }) else {
                throw NativeSpacesError.invalidSnapshot("window IDs must be nonzero, at most 1024 per read")
            }
            ids = Array(Set(windowIDs)).sorted()
        } else {
            guard let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
                throw NativeSpacesError.unavailable("public window inventory unavailable")
            }
            ids = Array(Set(rows.compactMap { row -> UInt32? in
                guard let level = row[kCGWindowLayer as String] as? Int, level == 0,
                      let id = row[kCGWindowNumber as String] as? UInt32, id != 0 else { return nil }
                return id
            })).sorted()
            guard ids.count <= 1024 else { throw NativeSpacesError.invalidSnapshot("window inventory exceeds read budget") }
        }
        let windows = try ids.map { id in
            try Task.checkCancellation()
            return NativeWindowMembership(windowID: id, spaceIDs: bridge.spaces(for: id))
        }
        // Detect a Space/topology transition during per-window IPC. Do not publish a
        // mixed-generation membership map as permission to move or tile anything.
        let confirmed = try NativeSpacesSnapshot.parseDisplays(bridge.copyDisplays())
        try Task.checkCancellation()
        guard topology == confirmed else { throw NativeSpacesError.invalidSnapshot("Space topology changed during read; retry after settling") }
        let duration = start.duration(to: .now).components
        let ms = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        return NativeSpacesSnapshot(displays: topology, windows: windows, readMilliseconds: ms, capturedAt: Date())
    }
}
