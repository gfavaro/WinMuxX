import Foundation

/// Bundle declaration is stable even when an accessory app temporarily adopts a Dock policy.
func appDeclaresAccessory(_ infoDictionary: [String: Any]?) -> Bool {
    guard let value = infoDictionary?["LSUIElement"] else { return false }
    if let string = value as? String {
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return false
        }
    }
    return (value as? NSNumber)?.boolValue ?? false
}
