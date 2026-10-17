import Common
import Foundation

extension DynamicConfigValue where Value == Double {
    var defaultAspectRatio: Double {
        switch self {
            case .constant(let value): value
            case .perMonitor(_, let value): value
        }
    }
    var aspectRatioRules: [PerMonitorValue<Double>] {
        if case .perMonitor(let rules, _) = self { return rules }
        return []
    }

}

func renderedAspectRatio(_ value: DynamicConfigValue<Double>) -> String {
    let rules = value.aspectRatioRules.map { rule in
        let pattern = rule.description.selector
        let escaped = pattern.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "{ monitor.\"\(escaped)\" = \(rule.value) }"
    }
    return rules.isEmpty ? String(value.defaultAspectRatio) : "[" + (rules + [String(value.defaultAspectRatio)]).joined(separator: ", ") + "]"
}
