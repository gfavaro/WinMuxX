import SwiftUI

struct ShortcutGeneralSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("start-at-login", load: { config.startAtLogin }) private var startAtLogin: Bool
    @SettingsDraft("auto-reload-config", load: { config.autoReloadConfig }) private var autoReloadConfig: Bool

    var body: some View {
        SettingsScrollView {
            SettingsSection("Startup") {
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
