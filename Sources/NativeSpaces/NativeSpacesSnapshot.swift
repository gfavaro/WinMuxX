import Foundation

public enum NativeSpacesError: Error, Equatable, CustomStringConvertible {
    case unavailable(String)
    case invalidSnapshot(String)

    public var description: String {
        switch self {
        case .unavailable(let reason): "Native Spaces unavailable: \(reason)"
        case .invalidSnapshot(let reason): "Native Spaces snapshot rejected: \(reason)"
        }
    }
}

public struct NativeSpace: Codable, Equatable, Sendable {
    /// Decimal strings keep the complete 64-bit identity in JSON clients.
    public let id: String
    public let uuid: String?
    public let type: Int
    public var isDesktop: Bool { type == 0 }
}

public struct NativeSpaceDisplay: Codable, Equatable, Sendable {
    public let identifier: String
    public let activeSpaceID: String
    public let spaces: [NativeSpace]
}

public struct NativeWindowMembership: Codable, Equatable, Sendable {
    public let windowID: UInt32
    /// Empty and multiple memberships are deliberately retained, never guessed.
    public let spaceIDs: [String]?
    public var unambiguousSpaceID: String? {
        guard let spaceIDs, spaceIDs.count == 1 else { return nil }
        return spaceIDs[0]
    }
}

public struct NativeSpacesSnapshot: Codable, Equatable, Sendable {
    public let displays: [NativeSpaceDisplay]
    public let windows: [NativeWindowMembership]
    public let readMilliseconds: Double
    public let capturedAt: Date
    /// Spaces needing reconciliation, not a second membership model. Nil is a
    /// full diagnostic read. Unlisted Space trees remain retained and untouched.
    public var reconciliationSpaceIDs: [String]? = nil

    /// Parse only an intact topology. A missing row must not become a new empty desktop.
    public static func parseDisplays(_ raw: [[String: Any]]) throws -> [NativeSpaceDisplay] {
        guard !raw.isEmpty else { throw NativeSpacesError.invalidSnapshot("no displays") }
        var displayIDs = Set<String>()
        return try raw.map { row in
            guard let identifier = row["Display Identifier"] as? String, !identifier.isEmpty,
                  displayIDs.insert(identifier).inserted,
                  let current = row["Current Space"] as? [String: Any],
                  let active = spaceID(current),
                  let values = row["Spaces"] as? [[String: Any]], !values.isEmpty else {
                throw NativeSpacesError.invalidSnapshot("missing or duplicate display/active Space")
            }
            var ids = Set<String>()
            let spaces = try values.map { value -> NativeSpace in
                guard let id = spaceID(value), ids.insert(id).inserted,
                      let type = value["type"] as? NSNumber,
                      CFGetTypeID(type) != CFBooleanGetTypeID(),
                      let kind = Int(type.stringValue), kind >= 0 else {
                    throw NativeSpacesError.invalidSnapshot("missing Space identity/type or duplicate Space")
                }
                let uuid = (value["uuid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return NativeSpace(id: id, uuid: uuid, type: kind)
            }
            guard ids.contains(active) else {
                throw NativeSpacesError.invalidSnapshot("active Space absent from display's Space list")
            }
            return NativeSpaceDisplay(identifier: identifier, activeSpaceID: active, spaces: spaces)
        }
    }

    private static func spaceID(_ value: [String: Any]) -> String? {
        // Do not coerce missing IDs, Boolean values, zero, fractions or negative IDs.
        func decode(_ raw: Any?) -> String? {
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  let id = UInt64(n.stringValue), id != 0 else { return nil }
            return String(id)
        }
        let id64 = decode(value["id64"])
        let managed = decode(value["ManagedSpaceID"])
        if value["id64"] != nil && id64 == nil { return nil }
        if value["ManagedSpaceID"] != nil && managed == nil { return nil }
        if let id64, let managed, id64 != managed { return nil }
        return id64 ?? managed
    }
}
