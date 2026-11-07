import SwiftUI

struct ShortcutGeneralSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("start-at-login", load: { config.startAtLogin }) private var startAtLogin: Bool
    @SettingsDraft("auto-reload-config", load: { config.autoReloadConfig }) private var autoReloadConfig: Bool

    @SettingsDraft("start-workspaces-on-main-monitor", load: { config.startWorkspacesOnMainMonitor }) private var startWorkspacesOnMain: Bool

    var body: some View {
        SettingsScrollView {
            SettingsSection("Startup") {
                SettingsToggle(.startWorkspacesOnMain, isOn: $startWorkspacesOnMain, help: "Start existing workspaces on main instead of restoring their displays. Explicit assignments and After startup commands can choose other displays. Takes effect next launch.") {
                    persistRootBool("start-workspaces-on-main-monitor", startWorkspacesOnMain)
                }
                SettingsToggle(.startAtLogin, isOn: $startAtLogin, help: "Launch WinMuxX after you sign in.") {
                    persistRootBool("start-at-login", startAtLogin)
                }
            }
            SettingsSection("Configuration") {
                SettingsToggle(.autoReloadConfig, isOn: $autoReloadConfig, help: "Apply valid edits saved from another editor automatically.") {
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

    private func persistRootBool(_ key: String, _ value: Bool) {
        persistSettingsConfig(section: nil, key: key, renderedValue: value ? "true" : "false", model: model)
    }
}
