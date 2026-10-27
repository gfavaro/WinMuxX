import SwiftUI

struct ShortcutGeneralSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("start-at-login", load: { config.startAtLogin }) private var startAtLogin: Bool
    @SettingsDraft("auto-reload-config", load: { config.autoReloadConfig }) private var autoReloadConfig: Bool

    @SettingsDraft("start-workspaces-on-main-monitor", load: { config.startWorkspacesOnMainMonitor }) private var startWorkspacesOnMain: Bool
    /// Applied only by restarting: a running WinMuxX keeps its backend (see `reload-config`).
    @State private var backendChoice = WorkspaceBackendChoice.running

    var body: some View {
        SettingsScrollView {
            SettingsSection("Startup") {
                SettingsToggle("Start workspaces on main display", id: "start-workspaces-on-main-monitor", isOn: $startWorkspacesOnMain, help: "Start existing workspaces on main instead of restoring their displays. Explicit assignments and After startup commands can choose other displays. Takes effect next launch.") {
                    persistRootBool("start-workspaces-on-main-monitor", startWorkspacesOnMain)
                }
                SettingsToggle("Start at login", id: "start-at-login", isOn: $startAtLogin, help: "Launch WinMuxX after you sign in.") {
                    persistRootBool("start-at-login", startAtLogin)
                }
            }
            SettingsSection("Workspaces") {
                Picker("Workspaces", selection: $backendChoice) {
                    Text("WinMuxX workspaces").tag(WorkspaceBackendChoice.virtual)
                    Text("macOS Spaces, tiled (experimental)").tag(WorkspaceBackendChoice.nativeTiled)
                    Text("macOS Spaces, not tiled (experimental)").tag(WorkspaceBackendChoice.native)
                }
                Text("WinMuxX workspaces hide inactive windows off screen and move whole workspaces between displays. macOS Spaces keeps every window on a real desktop, so Mission Control and swipes between desktops work as usual.")
                    .font(.caption).foregroundStyle(.secondary)
                if backendChoice != .running {
                    HStack {
                        Text("Saves the choice and restarts WinMuxX.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart WinMuxX") { saveAndRestart(backendChoice) }
                    }
                }
            }
            SettingsSection("Configuration") {
                SettingsToggle("Reload config when it changes", id: "auto-reload-config", isOn: $autoReloadConfig, help: "Apply valid edits saved from another editor automatically.") {
                    persistRootBool("auto-reload-config", autoReloadConfig)
                }
            }
            SettingsSection("Setup Check") {
                SetupCheckView()
            }
            SettingsSection("Troubleshooting") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostics")
                        Text("Permissions, displays and tiling state, with a button to copy the report for a bug report.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Diagnostics…") { DiagnosticsWindowController.shared.show() }
                }
            }
        }
        .navigationTitle("General")

    }

    private func saveAndRestart(_ choice: WorkspaceBackendChoice) {
        do {
            _ = try model.configAccess.edit { applyingSettingsConfigEdits(choice.configEdits, to: $0) }
            relaunchApp()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func persistRootBool(_ key: String, _ value: Bool) {
        persistSettingsConfig(section: nil, key: key, renderedValue: value ? "true" : "false", model: model)
    }
}

enum WorkspaceBackendChoice: Hashable {
    case virtual, native, nativeTiled

    var configEdits: [SettingsConfigEdit] {
        [
            SettingsConfigEdit(section: "workspace-backend", key: "type", renderedValue: self == .virtual ? "'virtual'" : "'native'"),
            SettingsConfigEdit(section: "native-spaces", key: "tiling-enabled", renderedValue: self == .nativeTiled ? "true" : "false"),
        ]
    }

    @MainActor static var running: Self {
        switch runtime.workspaceBackend.kind {
            case .virtual: .virtual
            case .native: runtime.workspaceBackend.nativeTilingEnabled ? .nativeTiled : .native
        }
    }
}
