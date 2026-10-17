import SwiftUI

struct ShortcutGeneralSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("start-at-login", load: { config.startAtLogin }) private var startAtLogin: Bool
    @SettingsDraft("auto-reload-config", load: { config.autoReloadConfig }) private var autoReloadConfig: Bool

    @SettingsDraft("start-workspaces-on-main-monitor", load: { config.startWorkspacesOnMainMonitor }) private var startWorkspacesOnMain: Bool

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
            SettingsSection("Configuration") {
                SettingsToggle("Reload config when it changes", id: "auto-reload-config", isOn: $autoReloadConfig, help: "Apply valid edits saved from another editor automatically.") {
                    persistRootBool("auto-reload-config", autoReloadConfig)
                }
            }
        }
        .navigationTitle("General")

    }

    private func persistRootBool(_ key: String, _ value: Bool) {
        persistSettingsConfig(section: nil, key: key, renderedValue: value ? "true" : "false", model: model)
    }
}
