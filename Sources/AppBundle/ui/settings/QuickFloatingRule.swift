import Foundation
import TOMLKit

enum QuickFloatingRuleMatch: Equatable {
    case application
    case exactTitle(String)
    case titlePrefix(String)
}

struct QuickFloatingRuleConflict: Equatable {
    let ruleIndex: Int
    let actions: [String]
}

enum QuickFloatingRuleDocument {
    static func conflict(in text: String, bundleId: String, appName: String?, title: String?) -> QuickFloatingRuleConflict? {
        guard let table = try? TOMLTable(string: text), let rules = table["on-window-detected"]?.array else { return nil }
        for (index, value) in rules.enumerated() {
            guard let rule = value.table else { continue }
            let continues = rule["check-further-callbacks"]?.bool ?? false
            guard !continues, let matcher = rule["if"]?.table,
                  couldMatch(matcher, bundleId: bundleId, appName: appName, title: title) else { continue }
            let actions = rule["run"]?.string.map { [$0] } ?? rule["run"]?.array?.compactMap(\.string) ?? []
            return QuickFloatingRuleConflict(ruleIndex: index, actions: actions)
        }
        return nil
    }

    static func rule(bundleId: String, match: QuickFloatingRuleMatch) -> String {
        var fields = ["if.app-id = \(settingsQuotedString(bundleId))"]
        switch match {
            case .application: break
            case .exactTitle(let title): fields.append("if.window-title-regex-substring = \(settingsQuotedString("^" + NSRegularExpression.escapedPattern(for: title) + "$"))")
            case .titlePrefix(let title): fields.append("if.window-title-regex-substring = \(settingsQuotedString("^" + NSRegularExpression.escapedPattern(for: title)))")
        }
        return "[[on-window-detected]]\n" + fields.joined(separator: "\n") + "\nrun = 'layout floating'\n"
    }

    static func adding(_ rule: String, to text: String) throws -> String {
        try SettingsRuleDocument(text).adding(rule, in: text)
    }

    static func matchesTitle(_ title: String, with match: QuickFloatingRuleMatch) -> Bool {
        switch match {
            case .application: true
            case .exactTitle(let value): title == value
            case .titlePrefix(let value): title.hasPrefix(value)
        }
    }

    private static func couldMatch(_ matcher: TOMLTable, bundleId: String, appName: String?, title: String?) -> Bool {
        if let exact = matcher["app-id"]?.string, exact != bundleId { return false }
        if let pattern = matcher["app-id-regex"]?.string, !regex(pattern, matches: bundleId) { return false }
        if let pattern = matcher["app-name-regex-substring"]?.string {
            guard let appName, regex(pattern, matches: appName) else { return false }
        }
        if let pattern = matcher["window-title-regex-substring"]?.string {
            guard let title, regex(pattern, matches: title) else { return false }
        }
        // Workspace/startup constraints can still match on a future detection.
        return true
    }

    private static func regex(_ pattern: String, matches value: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return true }
        let range = NSRange(value.startIndex..., in: value)
        return expression.firstMatch(in: value, range: range) != nil
    }
}
