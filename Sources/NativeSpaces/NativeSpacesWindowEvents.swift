import Darwin
import Foundation

struct NativeSpacesWindowEvent: Equatable, Sendable {
    static let kinds: [UInt32] = [804, 815, 816, 1325, 1326, 1327, 1328, 1401]
    let kind: UInt32
    let windowID: UInt32?
    var changesTopology: Bool { [1327, 1328, 1401].contains(kind) }
    var confirmsClosure: Bool { kind == 804 }

    /// Dinky/JankyBorders event ABI: creation/Space departure carry an 8-byte
    /// Space ID before the window ID. A departure never proves destruction.
    static func decode(kind: UInt32, bytes: UnsafeRawBufferPointer) -> Self? {
        guard kinds.contains(kind) else { return nil }
        if kind == 1401 { return Self(kind: kind, windowID: nil) }
        if [1327, 1328].contains(kind) {
            guard bytes.count >= 8, bytes.loadUnaligned(as: UInt64.self) != 0 else { return nil }
            return Self(kind: kind, windowID: nil)
        }
        let offset = [1325, 1326].contains(kind) ? 8 : 0
        guard bytes.count >= offset + 4 else { return nil }
        let id = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        guard id != 0 else { return nil }
        return Self(kind: kind, windowID: id)
    }
}

/// One native read-side event owner, with independently removable subscribers.
/// Existing virtual-mode notification handlers remain owned by their subsystem.
/// Native observation does not initialize those virtual handlers.
@MainActor
final class NativeSpacesWindowEvents {
    static let shared = NativeSpacesWindowEvents()
    private typealias Callback = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
    private typealias Notify = @convention(c) (Callback, UInt32, UnsafeMutableRawPointer?) -> Int32
    private typealias Request = @convention(c) (Int32, UnsafePointer<UInt32>?, Int32) -> Int32
    private typealias Connection = @convention(c) () -> Int32
    private let register: Notify?
    private let remove: Notify?
    private let request: Request?
    private let connection: Connection?
    private var subscribers: [UUID: (NativeSpacesWindowEvent) -> Void] = [:]
    private var registered: [UInt32] = []
    private var watched: [UUID: Set<UInt32>] = [:]
    private var lastRequested: Set<UInt32>?
    private var healthy = true
    // Process lifetime: function pointers are never used after unloading SkyLight.
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    private static let callback: Callback = { kind, data, length, _ in
        let bytes = UnsafeRawBufferPointer(start: data, count: data == nil ? 0 : max(length, 0))
        guard let event = NativeSpacesWindowEvent.decode(kind: kind, bytes: bytes) else { return }
        DispatchQueue.main.async { NativeSpacesWindowEvents.shared.publish(event) }
    }

    private init() {
        register = Self.library.flatMap { dlsym($0, "SLSRegisterNotifyProc") }.map { unsafeBitCast($0, to: Notify.self) }
        remove = Self.library.flatMap { dlsym($0, "SLSRemoveNotifyProc") }.map { unsafeBitCast($0, to: Notify.self) }
        request = Self.library.flatMap { dlsym($0, "SLSRequestNotificationsForWindows") }.map { unsafeBitCast($0, to: Request.self) }
        connection = Self.library.flatMap { dlsym($0, "SLSMainConnectionID") }.map { unsafeBitCast($0, to: Connection.self) }
    }

    func subscribe(_ receive: @escaping (NativeSpacesWindowEvent) -> Void) -> UUID? {
        guard healthy, let register, let remove, request != nil, connection != nil else { return nil }
        if registered.isEmpty {
            for kind in NativeSpacesWindowEvent.kinds {
                guard register(Self.callback, kind, nil) == 0 else {
                    for previous in registered + [kind] {
                        if remove(Self.callback, previous, nil) != 0 { healthy = false }
                    }
                    registered = []
                    return nil
                }
                registered.append(kind)
            }
        }
        let id = UUID()
        subscribers[id] = receive
        return id
    }

    func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
        watched[id] = nil
        lastRequested = nil
        guard subscribers.isEmpty, let remove else { return }
        for kind in registered { if remove(Self.callback, kind, nil) != 0 { healthy = false } }
        registered = []
    }

    func watch(_ ids: Set<UInt32>, subscriber: UUID) -> Bool {
        guard subscribers[subscriber] != nil, let request, let connection else { return false }
        let combined = watched.filter { $0.key != subscriber }.values.reduce(ids) { $0.union($1) }
        guard combined.count <= 1024, !combined.contains(0) else { return false }
        watched[subscriber] = ids
        if combined == lastRequested { return true }
        let values = combined.sorted()
        guard values.isEmpty || values.withUnsafeBufferPointer({ request(connection(), $0.baseAddress, Int32($0.count)) }) == 0 else {
            lastRequested = nil
            return false
        }
        lastRequested = combined
        return true
    }

    private func publish(_ event: NativeSpacesWindowEvent) {
        for receive in Array(subscribers.values) { receive(event) }
    }
}
