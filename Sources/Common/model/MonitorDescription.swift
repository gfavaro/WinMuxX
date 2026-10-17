import Foundation

public enum MonitorDescription: Equatable, Sendable {
    case sequenceNumber(Int)
    case uuid(String)
    case hardware(MonitorHardwareIdentity)
    case main
    case secondary
    case pattern(String, SendableRegex<AnyRegexOutput>)

    public static func == (lhs: MonitorDescription, rhs: MonitorDescription) -> Bool {
        return switch (lhs, rhs) {
            case (.uuid(let a), .uuid(let b)): a == b
            case (.hardware(let a), .hardware(let b)): a == b
            case (.main, .main): true
            case (.secondary, .secondary): true
            case (.sequenceNumber(let a), .sequenceNumber(let b)): a == b
            case (.pattern(let a, _), .pattern(let b, _)): a == b
            default: false
        }
    }

    public var selector: String {
        switch self {
            case .sequenceNumber(let number): String(number)
            case .uuid(let value): "uuid:\(value)"
            case .hardware(let identity): identity.selector
            case .main: "main"
            case .secondary: "secondary"
            case .pattern(let value, _): value
        }
    }

    public static func caseSensitivePattern(_ raw: String) -> MonitorDescription? {
        (try? SendableRegex(raw)).flatMap { .pattern(raw, $0) }
    }
}

public func parseMonitorDescription(_ raw: String) -> Parsed<MonitorDescription> {
    if raw.lowercased().hasPrefix("hardware:") {
        let parts = raw.dropFirst(9).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, let vendor = UInt32(parts[0]), let model = UInt32(parts[1]),
              let serial = UInt32(parts[2]), let identity = MonitorHardwareIdentity(vendor: vendor, model: model, serial: serial)
        else { return .failure("Invalid hardware selector; use hardware:<vendor>:<model>:<serial> with nonzero decimal IDs") }
        return .success(.hardware(identity))
    }
    if raw.lowercased().hasPrefix("uuid:") {
        guard let uuid = UUID(uuidString: String(raw.dropFirst(5))) else { return .failure("Invalid monitor UUID: \(raw)") }
        return .success(.uuid(uuid.uuidString))
    }
    if let int = Int(raw) {
        return int >= 1
            ? .success(.sequenceNumber(int))
            : .failure("Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal")
    }
    if raw == "main" {
        return .success(.main)
    }
    if raw == "secondary" {
        return .success(.secondary)
    }

    return raw.isEmpty
        ? .failure("Empty string is an illegal monitor description")
        : parseCaseInsensitiveRegex(raw).map { MonitorDescription.pattern(raw, .init($0)) }
}

public func parseCaseInsensitiveRegex(_ raw: String) -> Parsed<Regex<AnyRegexOutput>> {
    Result { try Regex(raw) }
        .mapError { e in "Can't parse '\(raw)' regex. \(e.localizedDescription)" }
        .map { $0.ignoresCase() }
}

/// Circumvent Regex not being Sendable by default
public struct SendableRegex<Output>: Sendable {
    nonisolated(unsafe) public let val: Regex<Output>
    init(_ regex: Regex<Output>) { self.val = regex }
    // init(_ str: String) { self.regex = regex }
}

extension SendableRegex where Output == AnyRegexOutput {
    public init(_ pattern: String) throws {
        self = SendableRegex(try Regex(pattern))
    }
}

public struct MonitorHardwareIdentity: Equatable, Hashable, Sendable {
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32

    public init?(vendor: UInt32, model: UInt32, serial: UInt32) {
        guard vendor != 0, model != 0, serial != 0 else { return nil }
        self.vendor = vendor; self.model = model; self.serial = serial
    }

    public var selector: String { "hardware:\(vendor):\(model):\(serial)" }
}
