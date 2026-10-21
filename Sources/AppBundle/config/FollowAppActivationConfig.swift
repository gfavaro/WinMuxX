import Common
import TOMLKit

struct FollowAppActivationConfig: ConvenienceCopyable {
    var enabled = true
    var excludeApps: [String] = []
    func follows(_ bundleId: String?) -> Bool {
        enabled && !(bundleId.map { excludeApps.contains($0) } ?? false)
    }
}

func parseFollowAppActivation(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace,
                             _ errors: inout [TomlParseError]) -> FollowAppActivationConfig {
    if let value = raw.bool { return FollowAppActivationConfig(enabled: value) }
    return parseTable(raw, FollowAppActivationConfig(), [
        "enabled": Parser(\.enabled, parseBool),
        "exclude-apps": Parser(\.excludeApps, parseArrayOfStrings),
    ], trace, &errors)
}
