import AppKit
import Common
import SwiftUI

struct SettingsDisplayRow: Identifiable, Equatable {
    let id: String
    let name: String
    let resolution: String
    let isMain: Bool
    let uuid: String?
    let hardware: String?
    let workspaces: [String]
    let activeWorkspace: String?
}

@MainActor
final class SettingsDisplaysModel: ObservableObject {
    @Published private(set) var rows: [SettingsDisplayRow] = []
    @Published var assignment = SettingsAssignmentDraft()

    func refresh() {
        let next = sortedMonitors.map { monitor in
            SettingsDisplayRow(
                id: monitor.displayUUID.map { "uuid:\($0)" } ?? "index:\(monitor.monitorAppKitNsScreenScreensId)",
                name: monitor.name, resolution: "\(Int(monitor.width)) × \(Int(monitor.height)) pt",
                isMain: monitor.isMain, uuid: monitor.displayUUID,
                hardware: monitor.hardwareIdentity?.selector,
                workspaces: Workspace.all.filter { $0.assignedMonitor?.rect == monitor.rect }.map(\.name).sorted(),
                activeWorkspace: runtime.workspaces.visibleWorkspace(for: monitor)?.name,
            )
        }
        setIfChanged(\.rows, next)
    }

    func bringHere(workspace: String, selector: String, expectedVisibleWorkspace: String? = nil) async throws {
        // Re-resolve after confirmation. A disconnected display must not become another destination.
        guard let description = parseMonitorDescription(selector).getOrNil(),
              description.resolveMonitor(sortedMonitors: sortedMonitors) != nil,
              Workspace.existing(byName: workspace) != nil,
              let token: RunSessionGuard = .isServerEnabled,
              let command = parseCommand(["move-workspace-to-monitor", selector]).cmdOrNil
        else { throw SettingsDisplayError("The workspace or display is no longer available.") }
        try await runLightSession(.menuBarButton, token) {
            guard let currentMonitor = description.resolveMonitor(sortedMonitors: sortedMonitors),
                  Workspace.existing(byName: workspace) != nil else {
                throw SettingsDisplayError("The workspace or display is no longer available.")
            }
            if let expectedVisibleWorkspace,
               runtime.workspaces.visibleWorkspace(for: currentMonitor)?.name != expectedVisibleWorkspace {
                throw SettingsDisplayError("The destination workspace changed. Review the move and try again.")
            }
            let result = try await command.run(CmdEnv(workspaceName: workspace), .emptyStdin)
            guard result.exitCode == 0 else { throw SettingsDisplayError(result.stderr.joined(separator: "\n")) }
            _ = Workspace.existing(byName: workspace)?.focusWorkspace()
        }
        refresh()
    }
}

struct SettingsDisplayError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
func validateSecondarySettingsAssignments(_ text: String) throws {
    let parsed = parseConfig(text)
    guard parsed.errors.isEmpty else { throw SettingsDisplayError(parsed.errors.map(\.description).joined(separator: "\n")) }
    var used: Set<String> = []
    for selectors in parsed.config.workspaceToMonitorForceAssignment.values {
        guard let monitor = selectors.lazy.compactMap({ $0.resolveMonitor(sortedMonitors: sortedMonitors) }).first,
              !monitor.isMain else { continue }
        let key = monitor.displayUUID ?? String(monitor.monitorAppKitNsScreenScreensId)
        guard used.insert(key).inserted else { throw SettingsDisplayError("Only one workspace may be assigned to each secondary display.") }
    }
}

struct SettingsDisplaysView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @ObservedObject var displays: SettingsDisplaysModel
    @ObservedObject private var tray = TrayMenuModel.shared
    @State private var isSavingAssignment = false
    @State private var attemptedAssignment: SettingsAssignmentDraft?
    @State private var workspace = ""
    @State private var layoutWorkspace = ""
    @State private var workspaceLayoutChoice = "inherit"
    @State private var selectedDisplay: String?
    @State private var pendingMove: (workspace: String, selector: String, visibleWorkspace: String?, displayName: String)?
    @State private var confirmsMove = false
    @State private var error: String?
    var onGeneral: () -> Void

    var body: some View {
        SettingsScrollView {
            SettingsSection("Connected displays") {
                if displays.rows.isEmpty { SettingsDescription("No connected displays are available. Saved assignments remain unchanged.") }
                ForEach(displays.rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.name).font(.headline)
                            if row.isMain { Text("Main").foregroundStyle(.secondary) }
                            Spacer()
                            Text(row.resolution).foregroundStyle(.secondary)
                        }
                        Text("Workspaces: " + (row.workspaces.isEmpty ? "None" : row.workspaces.map { workspaceDisplayName($0) }.joined(separator: ", ")))
                        if let uuid = row.uuid {
                            HStack {
                                Text(uuid).font(.caption.monospaced()).textSelection(.enabled)
                                Button("Copy UUID") { copy("uuid:" + uuid) }
                            }
                        }
                        if let hardware = row.hardware {
                            Button("Copy hardware selector") { copy(hardware) }
                        }
                    }.padding(.vertical, 6)
                }
            }
            SettingsSection("Workspace layout mode") {
                Picker("Workspace", selection: $layoutWorkspace) {
                    Text("Choose workspace").tag("")
                    ForEach(tray.workspaces, id: \.name) { row in Text(row.displayName).tag(row.name) }
                }
                Picker("Default mode", selection: $workspaceLayoutChoice) {
                    Text("Inherit global default").tag("inherit")
                    Text("Dwindle").tag("dwindle")
                    Text("Master").tag("master")
                    Text("Scrolling").tag("scrolling")
                }
                Button("Save workspace mode") { saveWorkspaceLayout() }
                    .disabled(layoutWorkspace.isEmpty || workspaceLayoutChoice == currentWorkspaceLayoutChoice)
                SettingsDescription("Sets the workspace-wide arrangement. Each existing top-level group keeps its nested splits and tabs. A matching display override may take precedence.")
            }
            SettingsSection("Move a workspace") {
                Picker("Workspace", selection: $workspace) {
                    Text("Choose workspace").tag("")
                    ForEach(tray.workspaces, id: \.name) { row in Text(row.displayName).tag(row.name) }
                }
                Picker("Destination", selection: $selectedDisplay) {
                    Text("Choose display").tag(nil as String?)
                    ForEach(displays.rows.filter { $0.uuid != nil }) { row in Text(row.name).tag(Optional(row.id)) }
                }
                Button("Bring Here…") {
                    guard let selectedDisplay else { return }
                    guard let row = displays.rows.first(where: { $0.id == selectedDisplay }) else { return }
                    pendingMove = (workspace, selectedDisplay, row.activeWorkspace, row.name)
                    confirmsMove = true
                }.disabled(workspace.isEmpty || selectedDisplay == nil)
                SettingsDescription("Moves this workspace now. A secondary display keeps one workspace; its previous workspace returns to main. Saved assignments are unchanged.")
            }
            SettingsSection("Configured assignments") {
                if config.workspaceToMonitorForceAssignment.isEmpty {
                    SettingsDescription("No saved display assignments. Workspaces keep their current owner until explicitly moved.")
                }
                ForEach(config.workspaceToMonitorForceAssignment.keys.sorted(), id: \.self) { name in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workspaceDisplayName(name))
                            Text(assignmentSummary(name)).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).help(assignmentSummary(name))
                        }
                        Spacer()
                        Button("Edit") { editAssignment(name) }
                        Button("Remove") { removeAssignment(name) }
                    }
                }
                assignmentEditor
                SettingsDescription("Saved assignments constrain placement, including after startup. Bring Here remains a separate one-time move.")
                Button("Startup options…", action: onGeneral)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .onAppear { displays.refresh(); loadWorkspaceLayoutChoice() }
        .onChange(of: layoutWorkspace) { _ in loadWorkspaceLayoutChoice() }
        .onReceive(tray.$workspaceSidebarWorkspaces) { _ in displays.refresh() }
        .onReceive(tray.$workspaceSidebarMonitorScopes) { _ in displays.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).receive(on: RunLoop.main)) { _ in displays.refresh() }
        .alert("Bring this workspace here?", isPresented: $confirmsMove) {
            Button("Cancel", role: .cancel) { pendingMove = nil }
            Button("Bring Here") {
                guard let request = pendingMove else { return }
                pendingMove = nil
                Task { @MainActor in
                    do { try await displays.bringHere(workspace: request.workspace, selector: request.selector, expectedVisibleWorkspace: request.visibleWorkspace); error = nil }
                    catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            if let request = pendingMove {
                Text("Bring \(workspaceDisplayName(request.workspace)) to \(request.displayName)? Currently showing \(request.visibleWorkspace.map(workspaceDisplayName) ?? "no workspace"). If this is a secondary display, its previous workspace returns to main.")
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var currentWorkspaceLayoutChoice: String {
        guard !layoutWorkspace.isEmpty else { return "inherit" }
        return config.workspaceLayouts[layoutWorkspace]?.defaults.layout?.rawValue ?? "inherit"
    }

    private func loadWorkspaceLayoutChoice() { workspaceLayoutChoice = currentWorkspaceLayoutChoice }

    private func saveWorkspaceLayout() {
        guard !layoutWorkspace.isEmpty, workspaceLayoutChoice != currentWorkspaceLayoutChoice else { return }
        let name = layoutWorkspace
        let selected = workspaceLayoutChoice
        let previous = currentWorkspaceLayoutChoice
        let settingId = "workspace.\(name).layout"
        model.activeSettingTitle = "Workspace layout: \(workspaceDisplayName(name))"
        persistSettingsDocumentEdit(model: model, settingIDs: [settingId], onSaved: {
            error = nil
        }, onFailure: { failure in
            error = failure.localizedDescription
        }) { current in
            let parsed = parseConfig(current)
            guard parsed.errors.isEmpty,
                  (parsed.config.workspaceLayouts[name]?.defaults.layout?.rawValue ?? "inherit") == previous else {
                throw ConfigFileStore.Conflict()
            }
            let rendered = selected == "inherit" ? nil : settingsQuotedString(selected)
            return applyingSettingsConfigEdits([
                .init(section: "workspace.\(settingsQuotedString(name))", key: "layout", renderedValue: rendered),
            ], to: current)
        }
    }

    private var assignmentEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if displays.assignment.isEditing {
                LabeledContent("Workspace", value: workspaceDisplayName(displays.assignment.workspace))
            } else {
                Picker("Workspace", selection: $displays.assignment.workspace) {
                    Text("Choose workspace").tag("")
                    ForEach(tray.workspaces, id: \.name) { row in Text(row.displayName).tag(row.name) }
                    if !displays.assignment.workspace.isEmpty && !tray.workspaces.contains(where: { $0.name == displays.assignment.workspace }) {
                        Text(displays.assignment.workspace + " (future workspace)").tag(displays.assignment.workspace)
                    }
                }
            }
            if !displays.assignment.advanced {
                Picker("Display", selection: $displays.assignment.selector) {
                    Text("Choose display").tag("")
                    ForEach(displays.rows.filter { $0.uuid != nil }) { row in Text(row.name).tag(row.id) }
                    if !displays.assignment.selector.isEmpty && !displays.rows.contains(where: { $0.id == displays.assignment.selector }) {
                        Text("Current advanced selection — " + displays.assignment.selector).tag(displays.assignment.selector)
                    }
                }
            }
            DisclosureGroup("Advanced", isExpanded: $displays.assignment.advanced) {
                if !displays.assignment.isEditing {
                    SettingsEditorField("Workspace name", prompt: "Internal name for an existing or future workspace", text: $displays.assignment.workspace)
                }
                SettingsEditorField("Display selector", prompt: "uuid:…, hardware:… or an array", text: $displays.assignment.selector)
                SettingsDescription("Use UUIDs for exact displays. Arrays retain ordered alternatives. Unavailable assignments are kept until you explicitly change them.")
            }
            HStack {
                if !displays.assignment.isEditing {
                    Button("Add assignment") { saveAssignment() }
                        .disabled(!displays.assignment.isDirty || displays.assignment.workspace.isEmpty || displays.assignment.selector.isEmpty)
                }
                if isSavingAssignment { Text("Saving…").foregroundStyle(.secondary) }
                if displays.assignment.isDirty || displays.assignment.isEditing {
                    Button(displays.assignment.isDirty ? "Discard changes" : "Done") { displays.assignment = SettingsAssignmentDraft() }
                }
            }
        }
        .disabled(isSavingAssignment || model.savingSettingIDs.contains("workspace-to-monitor-force-assignment"))
        .settingsAutosave(value: displays.assignment, enabled: displays.assignment.isEditing && displays.assignment.isDirty && !isSavingAssignment && displays.assignment != attemptedAssignment) {
            guard displays.assignment.isDirty, displays.assignment != attemptedAssignment else { return }
            do { _ = try displays.assignment.renderedSelectors() }
            catch { self.error = error.localizedDescription; return }
            saveAssignment()
        }
    }

    private func assignmentSummary(_ name: String) -> String {
        config.workspaceToMonitorForceAssignment[name, default: []].map { selector in
            if let row = displays.rows.first(where: { $0.id == selector.selector }) { return row.name }
            if selector.resolveMonitor(sortedMonitors: sortedMonitors) != nil { return selector.selector }
            return selector.selector + " (unavailable)"
        }.joined(separator: " → ")
    }

    private func editAssignment(_ name: String) {
        guard !displays.assignment.isDirty else { error = "Finish or discard the current assignment first."; return }
        displays.assignment = .editing(workspace: name, selectors: config.workspaceToMonitorForceAssignment[name, default: []].map(\.selector), connectedSelectors: Set(displays.rows.filter { $0.uuid != nil }.map(\.id)))
        error = nil
    }

    private func saveAssignment() {
        guard !isSavingAssignment else { return }
        let submitted = displays.assignment
        attemptedAssignment = submitted
        isSavingAssignment = true
        model.activeSettingTitle = "Display assignment"
        persistSettingsDocumentEdit(model: model, settingIDs: ["workspace-to-monitor-force-assignment"], onSaved: {
            isSavingAssignment = false
            if displays.assignment == submitted {
                displays.assignment = .editing(workspace: submitted.workspace,
                    selectors: config.workspaceToMonitorForceAssignment[submitted.workspace, default: []].map(\.selector),
                    connectedSelectors: Set(displays.rows.filter { $0.uuid != nil }.map(\.id)))
            }
            error = nil
        }, onFailure: { failure in
            isSavingAssignment = false
            error = failure.localizedDescription
        }) { current in try submitted.applying(to: current) }
    }

    private func removeAssignment(_ name: String) {
        guard !displays.assignment.isDirty else { error = "Finish or discard the current assignment first."; return }
        let original = config.workspaceToMonitorForceAssignment[name]?.map(\.selector)
        model.activeSettingTitle = "Display assignment"
        persistSettingsDocumentEdit(model: model, settingIDs: ["workspace-to-monitor-force-assignment"], onSaved: {
            if displays.assignment.workspace == name { displays.assignment = SettingsAssignmentDraft() }
        }) { current in
            guard parseConfig(current).config.workspaceToMonitorForceAssignment[name]?.map(\.selector) == original else { throw ConfigFileStore.Conflict() }
            return applyingSettingsConfigEdits([.init(section: "workspace-to-monitor-force-assignment", key: settingsQuotedString(name), renderedValue: nil)], to: current)
        }
    }
}
