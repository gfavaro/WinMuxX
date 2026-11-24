import AppKit
import SwiftUI

/// What the map shows, and the one save path for its edits. The text rules live in
/// `WorkspaceMapDocument`; this keeps the screen in step with the configuration file.
@MainActor
@Observable
final class SettingsWorkspaceMapModel {
    private(set) var routes: [WorkspaceMapRoute] = []
    private(set) var pinned: [Int] = []
    var error: String?
    private let readText: () throws -> String

    init(readText: @escaping () throws -> String = { try ConfigFileStore.read(preferredEditableConfigUrl()) ?? "" }) {
        self.readText = readText
    }

    /// Workspaces 1 to N, where N is the highest one that is routed to or kept, plus one to grow into.
    var tileCount: Int { max(routes.map(\.workspace).max() ?? 0, pinned.max() ?? 0, 1) + 1 }

    func apps(in workspace: Int) -> [String] { routes.filter { $0.workspace == workspace }.map(\.appId) }

    func load() {
        do {
            let text = try readText()
            routes = WorkspaceMapDocument.routes(in: text)
            pinned = WorkspaceMapDocument.pinned(in: text)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func assign(_ appId: String, to workspace: Int, using model: ShortcutSettingsModel) {
        save(model) { try WorkspaceMapDocument.assigning(appId: appId, workspace: workspace, in: $0) }
    }

    func remove(_ appId: String, using model: ShortcutSettingsModel) {
        save(model) { try WorkspaceMapDocument.removing(appId: appId, in: $0) }
    }

    func unpin(_ workspace: Int, using model: ShortcutSettingsModel) {
        save(model) { try WorkspaceMapDocument.unpinning(workspace: workspace, in: $0) }
    }

    private func save(_ model: ShortcutSettingsModel, _ edit: @escaping (String) throws -> String) {
        persistSettingsDocumentEdit(model: model, settingIDs: ["on-window-detected", "persistent-workspaces"],
                                    onSaved: { [weak self] in self?.load() },
                                    onFailure: { [weak self] in self?.error = $0.localizedDescription }, edit: edit)
    }
}

struct SettingsWorkspaceMapView: View {
    var model: ShortcutSettingsModel
    @State private var map = SettingsWorkspaceMapModel()

    var body: some View {
        SettingsScrollView {
            SettingsSection("Where apps open") {
                Text("Drop an app on a workspace and its windows open there. Workspaces 1 to the highest one used are kept, so Option-number always reaches them.")
                    .font(.callout).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(1...map.tileCount, id: \.self) { tile($0) }
                }
                if let error = map.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .onAppear { map.load() }
        .navigationTitle("Automation")
    }

    private func tile(_ number: Int) -> some View {
        let isNew = number == map.tileCount
        let isPinned = map.pinned.contains(number)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isNew ? "New" : String(number)).font(.headline)
                Spacer()
                if isPinned {
                    Button { map.unpin(number, using: model) } label: { Image(systemName: "pin.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Kept even when empty. Click to let it go.")
                        .accessibilityLabel("Unpin workspace \(number)")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(map.apps(in: number), id: \.self) { appId in
                    Image(nsImage: appIcon(appId)).resizable().frame(width: 32, height: 32)
                        .help(appName(appId))
                        .draggable(appId)
                        .contextMenu { Button("Stop opening \(appName(appId)) here") { map.remove(appId, using: model) } }
                        .accessibilityLabel(appName(appId))
                }
                addMenu(number)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(isNew ? 0.3 : 0.6)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: isNew ? [4] : [])))
        .dropDestination(for: String.self) { items, _ in
            guard let appId = items.first else { return false }
            map.assign(appId, to: number, using: model)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isNew ? "New workspace" : "Workspace \(number)")
    }

    private func addMenu(_ number: Int) -> some View {
        let routed = Set(map.routes.map(\.appId))
        let apps = runningApps().filter { !routed.contains($0.id) }
        return Menu {
            ForEach(apps, id: \.id) { app in
                Button(app.name) { map.assign(app.id, to: number, using: model) }
            }
        } label: {
            Image(systemName: "plus.circle").imageScale(.large)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .disabled(apps.isEmpty)
        .help("Add a running app")
        .accessibilityLabel("Add an app to workspace \(number)")
    }

    private func runningApps() -> [(id: String, name: String)] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own,
                  seen.insert(id).inserted else { return nil }
            return (id, app.localizedName ?? id)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func appIcon(_ bundleId: String) -> NSImage {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
            .map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private func appName(_ bundleId: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleId
    }
}
