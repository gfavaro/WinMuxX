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
