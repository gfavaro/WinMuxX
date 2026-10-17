import AppKit
import Common
import SwiftUI
import TOMLKit
import UniformTypeIdentifiers

struct SettingsRuleRow: Identifiable, Equatable {
    let id: Int
    let matches: String
    let actions: String

    init(id: Int, block: String) {
        self.id = id
        if let draft = try? SettingsRuleDraft(block: block) {
            var parts = [draft.appId, draft.appRegex, draft.titleRegex].filter { !$0.isEmpty }
            if !draft.workspace.isEmpty { parts.append("Workspace " + draft.workspace) }
            if draft.timing != "any" { parts.append(draft.timing.capitalized) }
            matches = parts.isEmpty ? "Any window" : parts.joined(separator: " · ")
        } else { matches = "Custom rule" }
        let row = (try? TOMLTable(string: block))?["on-window-detected"]?.array?.first?.table
        let commands = row?["run"]?.string.map { [$0] } ?? row?["run"]?.array?.compactMap(\.string) ?? []
        actions = commands.isEmpty ? "No actions" : commands.joined(separator: " → ")
    }
}

enum SettingsRulesLayout {
    static func usesSplit(width: CGFloat) -> Bool { width >= 720 }
}

struct GuidedRuleActions: Equatable {
    var layout = ""
    var workspace = ""

    init?(commands: [String]) {
        for raw in commands {
            guard let command = parseCommand(raw).cmdOrNil,
                  let words = try? raw.splitArgs().get() else { return nil }
            if command is LayoutCommand, words.count == 2,
               ["floating", "tiling"].contains(words[1]), layout.isEmpty, workspace.isEmpty {
                layout = words[1]
            } else if let move = command as? MoveNodeToWorkspaceCommand, words.count == 2,
                      case .direct = move.args.target.val, workspace.isEmpty {
                workspace = words[1]
            } else { return nil }
        }
    }

    var rendered: String {
        var commands: [String] = []
        if !layout.isEmpty { commands.append("layout \(layout)") }
        if !workspace.isEmpty { commands.append("move-node-to-workspace " + settingsQuotedString(workspace)) }
        return "[" + commands.map(settingsQuotedString).joined(separator: ", ") + "]"
    }
}

struct SettingsRuleDraft: Equatable {
    var appId = ""
    var appRegex = ""
    var titleRegex = ""
    var workspace = ""
    var timing = "any"
    var continues = false
    var guided: GuidedRuleActions?

    init(block: String) throws {
        guard let row = try TOMLTable(string: block)["on-window-detected"]?.array?.first?.table else {
            throw SettingsDisplayError("This rule needs the configuration editor.")
        }
        let match = row["if"]?.table
        appId = match?["app-id"]?.string ?? ""
        appRegex = match?["app-name-regex-substring"]?.string ?? ""
        titleRegex = match?["window-title-regex-substring"]?.string ?? ""
        workspace = match?["workspace"]?.string ?? ""
        timing = match?["during-winmux-startup"]?.bool.map { $0 ? "startup" : "runtime" } ?? "any"
        continues = row["check-further-callbacks"]?.bool ?? false
        let commands = row["run"]?.string.map { [$0] } ?? row["run"]?.array?.compactMap(\.string) ?? []
        guided = GuidedRuleActions(commands: commands)
    }

    func edits(from original: SettingsRuleDraft) -> [SettingsConfigEdit] {
        var edits: [SettingsConfigEdit] = []
        for (key, value, old) in [
            ("app-id", appId, original.appId),
            ("app-name-regex-substring", appRegex, original.appRegex),
            ("window-title-regex-substring", titleRegex, original.titleRegex),
            ("workspace", workspace, original.workspace),
        ] where value != old {
            edits.append(.init(section: "if", key: key, renderedValue: value.isEmpty ? nil : settingsQuotedString(value)))
        }
        if timing != original.timing {
            edits.append(.init(section: "if", key: "during-winmux-startup", renderedValue: timing == "any" ? nil : String(timing == "startup")))
        }
        if continues != original.continues {
            edits.append(.init(section: nil, key: "check-further-callbacks", renderedValue: String(continues)))
        }
        if guided != original.guided, let guided {
            edits.append(.init(section: nil, key: "run", renderedValue: guided.rendered))
        }
        return edits
    }
}

@MainActor
final class SettingsWindowRulesModel: ObservableObject {
    @Published private(set) var document = SettingsRuleDocument("")
    @Published private(set) var rows: [SettingsRuleRow] = []
    @Published private(set) var selection: Int?
    @Published var draft: SettingsRuleDraft?
    @Published private(set) var original: SettingsRuleDraft?
    @Published var error: String?
    private let readText: () throws -> String
    init(readText: @escaping () throws -> String = { try ConfigFileStore.read(preferredEditableConfigUrl()) ?? "" }) {
        self.readText = readText
    }
    @Published private(set) var isNewRule = false
    var isDirty: Bool { isNewRule || draft != original }

    func load() {
        guard !isDirty else { return }
        do {
            let text = try readText()
            document = SettingsRuleDocument(text)
            rows = document.entries.enumerated().map { SettingsRuleRow(id: $0.offset, block: $0.element.text) }
            let table = try TOMLTable(string: text)
            if let value = table["on-window-detected"], document.entries.isEmpty,
               value.array?.isEmpty != true {
                throw SettingsDisplayError("These rules use a custom TOML shape. Use the configuration editor to preserve them.")
            }
            if let selection, !document.entries.indices.contains(selection) { self.selection = nil }
            if let selection { try selectDraft(selection) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func select(_ index: Int) {
        guard !isDirty else { error = "Save or revert the current rule before selecting another."; return }
        do { try selectDraft(index); error = nil } catch { self.error = error.localizedDescription }
    }

    private func selectDraft(_ index: Int) throws {
        let value = try SettingsRuleDraft(block: document.entries[index].text)
        selection = index; draft = value; original = value
    }

    func revert() {
        if isNewRule { isNewRule = false; selection = nil; draft = nil; original = nil }
        else { draft = original }
        load()
    }

    func save(using model: ShortcutSettingsModel) {
        guard let selection, let draft, let original else { return }
        let baseline = document
        let creating = isNewRule
        persistSettingsDocumentEdit(model: model, settingIDs: ["on-window-detected"], onSaved: { [weak self] in
            guard let self else { return }
            self.isNewRule = false
            self.original = draft
            self.load()
        }) { current in
            let block = creating ? "[[on-window-detected]]\nrun = 'layout tiling'\n" : baseline.entries[selection].text
            let replacement = try SettingsRuleDocument.editing(block, edits: draft.edits(from: original))
            if creating {
                return try baseline.adding(replacement, in: current)
            }
            return try baseline.replacing(selection, with: replacement, in: current)
        }
    }

    func add() {
        guard !isDirty else { error = "Save or revert the current rule first."; return }
        load()
        guard error == nil else { return }
        do {
            let value = try SettingsRuleDraft(block: "[[on-window-detected]]\nrun = 'layout tiling'\n")
            selection = document.entries.count
            draft = value; original = value; isNewRule = true
        } catch { self.error = error.localizedDescription }
    }

    func change(using model: ShortcutSettingsModel, delete: Bool = false, offset: Int = 0) {
        guard let selection, !isDirty else { error = "Save or revert the current rule first."; return }
        let baseline = document
        persistSettingsDocumentEdit(model: model, settingIDs: ["on-window-detected"], onSaved: { [weak self] in
            self?.selection = nil; self?.draft = nil; self?.original = nil; self?.load()
        }) { current in
            if delete { return try baseline.replacing(selection, with: nil, in: current) }
            return try baseline.moving(selection, by: offset, in: current)
        }
    }
}

struct SettingsWindowRulesView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @ObservedObject var rules: SettingsWindowRulesModel
    var onRawEditor: () -> Void
    @State private var confirmsDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Window rules").font(.headline)
                Spacer()
                Button("Add rule") { rules.add() }
                Button("Configuration editor…", action: onRawEditor)
            }.padding(.horizontal, 20)
            GeometryReader { geometry in
                if SettingsRulesLayout.usesSplit(width: geometry.size.width) {
                    HSplitView {
                        ruleTable.frame(minWidth: 240, idealWidth: 280)
                        ruleDetail.frame(minWidth: 400)
                    }
                } else {
                    VStack(spacing: 0) {
                        ruleTable.frame(height: min(180, max(100, geometry.size.height * 0.35)))
                        Divider()
                        ruleDetail
                    }
                }
            }
            if let error = rules.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 20)
            }
            if rules.draft != nil { actionBar }
        }
        .disabled(model.savingSettingIDs.contains("on-window-detected"))
        .onAppear { rules.load() }
        .onChange(of: model.settingsRevision) { _ in rules.load() }
        .alert("Delete this rule?", isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { rules.change(using: model, delete: true) }
        }
    }

    private var ruleTable: some View {
        Table(rules.rows, selection: Binding(get: { rules.selection }, set: { if let index = $0 { rules.select(index) } })) {
            TableColumn("Matches") { row in
                Text(row.matches).lineLimit(2).help(row.matches)
            }
            TableColumn("Actions") { row in
                Text(row.actions).font(.system(.body, design: .monospaced)).lineLimit(2).help(row.actions)
            }
        }
        .overlay {
            if rules.rows.isEmpty { Text("No window rules").foregroundStyle(.secondary).allowsHitTesting(false) }
        }
        .accessibilityLabel("Window rules")
    }

    @ViewBuilder private var ruleDetail: some View {
        if rules.draft != nil {
            Form {
                Section("Match windows") {
                    SettingsEditorField("App ID", prompt: "Any app", text: field(\.appId))
                    Button("Choose app…") { chooseApp() }
                    SettingsEditorField("App name regex", prompt: "Any app name", text: field(\.appRegex))
                    SettingsEditorField("Window title regex", prompt: "Any window title", text: field(\.titleRegex))
                    DisclosureGroup("Additional matching options") {
                        SettingsEditorField("Workspace", prompt: "Any workspace", text: field(\.workspace))
                        Picker("Timing", selection: field(\.timing)) {
                            Text("Any").tag("any"); Text("Startup").tag("startup"); Text("Runtime").tag("runtime")
                        }
                        SettingsDescription("Regex matchers are case-insensitive. Empty fields match any value; all specified matchers must match.")
                    }
                }
                Section("Actions") {
                    if rules.draft?.guided != nil {
                        Picker("Layout", selection: guided(\.layout)) {
                            Text("Unchanged").tag(""); Text("Floating").tag("floating"); Text("Tiling").tag("tiling")
                        }
                        SettingsEditorField("Move window to workspace", prompt: "Keep its workspace", text: guided(\.workspace))
                    } else {
                        SettingsDescription("Custom actions are preserved. Use Configuration editor to change them.")
                    }
                    Toggle("Continue to later matching rules", isOn: field(\.continues))
                }
            }.formStyle(.grouped)
        } else {
            VStack(spacing: 8) {
                Text(rules.rows.isEmpty ? "Add your first rule" : "Select a rule").font(.headline)
                Text("Rules apply to newly detected windows.").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Button("Save") { rules.save(using: model) }.disabled(!rules.isDirty)
                Button("Revert") { rules.revert() }.disabled(!rules.isDirty)
                Spacer()
                Button("Move up") { rules.change(using: model, offset: -1) }.disabled((rules.selection ?? 0) == 0 || rules.isDirty)
                Button("Move down") { rules.change(using: model, offset: 1) }.disabled((rules.selection ?? 0) >= rules.document.entries.count - 1 || rules.isDirty)
                Button("Delete…", role: .destructive) { confirmsDelete = true }.disabled(rules.isDirty)
            }
            Text("Saved rules affect future window detections.").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 20).padding(.bottom, 12)
    }

    private func field<T>(_ path: WritableKeyPath<SettingsRuleDraft, T>) -> Binding<T> {
        let initial = rules.draft![keyPath: path]
        return Binding(get: { rules.draft?[keyPath: path] ?? initial }, set: { rules.draft?[keyPath: path] = $0 })
    }

    private func guided(_ path: WritableKeyPath<GuidedRuleActions, String>) -> Binding<String> {
        Binding(get: { rules.draft?.guided?[keyPath: path] ?? "" }, set: { rules.draft?.guided?[keyPath: path] = $0 })
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
            rules.draft?.appId = id
        }
    }
}
