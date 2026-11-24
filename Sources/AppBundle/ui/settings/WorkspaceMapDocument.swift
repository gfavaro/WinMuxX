import Foundation
import TOMLKit

/// An app routed to workspace `workspace` by a rule that matches only its bundle id and only
/// moves its windows there. Every other rule stays in Settings → Automation → Rules.
struct WorkspaceMapRoute: Equatable {
    let appId: String
    let workspace: Int
    let ruleIndex: Int
}

struct WorkspaceMapError: LocalizedError, Equatable {
    let errorDescription: String?
}

/// What the "Where apps open" map reads from, and writes to, the configuration text.
/// Workspaces are the numbers 1 to N: routing an app to N keeps 1…N, so Option-N always
/// reaches it. The rules are the same `on-window-detected` rules the Rules list edits.
enum WorkspaceMapDocument {
    static func routes(in text: String) -> [WorkspaceMapRoute] {
        SettingsRuleDocument(text).entries.enumerated().compactMap { index, entry in
            route(in: entry.text).map { WorkspaceMapRoute(appId: $0.appId, workspace: $0.workspace, ruleIndex: index) }
        }
    }

    static func pinned(in text: String) -> [Int] {
        persistentNames(in: text).compactMap(Int.init)
    }

    /// Routes `appId` to workspace `workspace` and keeps workspaces 1 to `workspace`.
    static func assigning(appId: String, workspace: Int, in text: String) throws -> String {
        guard workspace >= 1 else { throw WorkspaceMapError(errorDescription: "Workspaces start at 1.") }
        let document = SettingsRuleDocument(text)
        let rendered = renderedRun(workspace: workspace)
        var result: String
        if let existing = routes(in: text).first(where: { $0.appId == appId }) {
            let block = try SettingsRuleDocument.editing(document.entries[existing.ruleIndex].text,
                                                         edits: [SettingsConfigEdit(section: nil, key: "run", renderedValue: rendered)])
            result = try document.replacing(existing.ruleIndex, with: block, in: text)
        } else {
            // An earlier rule that stops the search for this app would win over the new one.
            if QuickFloatingRuleDocument.conflict(in: text, bundleId: appId, appName: nil, title: nil) != nil {
                throw WorkspaceMapError(errorDescription: "An earlier rule already handles this app. Edit it in Rules.")
            }
            let block = "[[on-window-detected]]\nif.app-id = \(settingsQuotedString(appId))\nrun = \(rendered)\n"
            result = try document.adding(block, in: text)
        }
        return pinning(upTo: workspace, in: result)
    }

    /// Stops routing `appId`. The workspace stays pinned: it may have been kept by hand.
    static func removing(appId: String, in text: String) throws -> String {
        guard let existing = routes(in: text).first(where: { $0.appId == appId }) else { return text }
        return try SettingsRuleDocument(text).replacing(existing.ruleIndex, with: nil, in: text)
    }

    /// Lets a workspace go again. Refused while an app is routed to it, or to a later one.
    static func unpinning(workspace: Int, in text: String) throws -> String {
        if routes(in: text).contains(where: { $0.workspace >= workspace }) {
            throw WorkspaceMapError(errorDescription: "Apps are routed to this workspace or a later one.")
        }
        let names = persistentNames(in: text).filter { Int($0) != workspace }
        return applyingSettingsConfigEdits([persistentEdit(names)], to: text)
    }

    // MARK: - Private

    private static func route(in block: String) -> (appId: String, workspace: Int)? {
        guard let row = try? TOMLTable(string: block)["on-window-detected"]?.array?.first?.table,
              row["check-further-callbacks"]?.bool != true,
              let match = row["if"]?.table, Set(match.keys) == ["app-id"], let appId = match["app-id"]?.string else { return nil }
        let commands = row["run"]?.string.map { [$0] } ?? row["run"]?.array?.compactMap(\.string) ?? []
        guard let actions = GuidedRuleActions(commands: commands), actions.layout.isEmpty,
              let workspace = Int(actions.workspace) else { return nil }
        return (appId, workspace)
    }

    private static func renderedRun(workspace: Int) -> String {
        var actions = GuidedRuleActions(commands: [])!
        actions.workspace = String(workspace)
        return actions.rendered
    }

    private static func persistentNames(in text: String) -> [String] {
        (try? TOMLTable(string: text))?["persistent-workspaces"]?.array?.compactMap(\.string) ?? []
    }

    private static func pinning(upTo count: Int, in text: String) -> String {
        let existing = persistentNames(in: text)
        let numbers = Set(existing.compactMap(Int.init)).union(1...count).sorted().map(String.init)
        let names = numbers + existing.filter { Int($0) == nil }
        guard names != existing else { return text }
        return applyingSettingsConfigEdits([persistentEdit(names)], to: text)
    }

    private static func persistentEdit(_ names: [String]) -> SettingsConfigEdit {
        SettingsConfigEdit(section: nil, key: "persistent-workspaces",
                           renderedValue: "[" + names.map(settingsQuotedString).joined(separator: ", ") + "]")
    }
}
