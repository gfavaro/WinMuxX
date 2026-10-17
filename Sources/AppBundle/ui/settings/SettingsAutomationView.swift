import SwiftUI

enum SettingsAutomationSection: String, CaseIterable {
    case rules, events
    static func restored(_ value: String) -> Self { Self(rawValue: value) ?? .rules }
}

struct ShortcutAutomationSettingsView: View {
    @AppStorage("settings.automationSection") private var storedSection = SettingsAutomationSection.rules.rawValue
    @ObservedObject var model: ShortcutSettingsModel
    @ObservedObject var rules: SettingsWindowRulesModel
    var onRawEditor: () -> Void
    @SettingsDraft("after-startup-command", load: { config.afterStartupCommand.map { $0.args.description }.joined(separator: "\n") }) private var startupCommands: String
    @SettingsDraft("exec-on-workspace-change", load: { config.execOnWorkspaceChange.joined(separator: "\n") }) private var workspaceCommands: String
    @SettingsDraft("on-focus-changed", load: { config.onFocusChanged.map { $0.args.description }.joined(separator: "\n") }) private var focusCommands: String
    @SettingsDraft("on-focused-monitor-changed", load: { config.onFocusedMonitorChanged.map { $0.args.description }.joined(separator: "\n") }) private var monitorCommands: String
    @SettingsDraft("on-mode-changed", load: { config.onModeChanged.map { $0.args.description }.joined(separator: "\n") }) private var modeCommands: String

    var body: some View {
        VStack(spacing: 12) {
            Picker("Automation section", selection: Binding(get: { SettingsAutomationSection.restored(storedSection) }, set: { storedSection = $0.rawValue })) {
                Text("Rules").tag(SettingsAutomationSection.rules)
                Text("Events").tag(SettingsAutomationSection.events)
            }.pickerStyle(.segmented).padding(.horizontal, 20)
            if SettingsAutomationSection.restored(storedSection) == .rules {
                SettingsWindowRulesView(model: model, rules: rules, onRawEditor: onRawEditor)
            } else { events }
        }
        .navigationTitle("Automation")
    }

    private var events: some View {
        SettingsScrollView {
            SettingsSection("Event actions") {
                SettingsMultilineField("On workspace change", id: "exec-on-workspace-change", text: $workspaceCommands, help: "One command per line. Commands run after changing workspaces.", savedValue: config.execOnWorkspaceChange.joined(separator: "\n")) { onSaved in saveCommands("exec-on-workspace-change", workspaceCommands, onSaved: onSaved) }
                SettingsMultilineField("On focus change", id: "on-focus-changed", text: $focusCommands, help: "One command per line. Commands run after the focused window changes.", savedValue: config.onFocusChanged.map { $0.args.description }.joined(separator: "\n")) { onSaved in saveCommands("on-focus-changed", focusCommands, onSaved: onSaved) }
                SettingsMultilineField("On focused monitor change", id: "on-focused-monitor-changed", text: $monitorCommands, help: "One command per line. Commands run after the active display changes.", savedValue: config.onFocusedMonitorChanged.map { $0.args.description }.joined(separator: "\n")) { onSaved in saveCommands("on-focused-monitor-changed", monitorCommands, onSaved: onSaved) }
                SettingsMultilineField("On mode change", id: "on-mode-changed", text: $modeCommands, help: "One command per line. Commands run after a mode changes.", savedValue: config.onModeChanged.map { $0.args.description }.joined(separator: "\n")) { onSaved in saveCommands("on-mode-changed", modeCommands, onSaved: onSaved) }
            }
            SettingsSection("Startup") {
                SettingsMultilineField(
                    "After startup",
                    text: $startupCommands,
                    help: "One command per line. Commands run after WinMuxX finishes starting.",
                    savedValue: config.afterStartupCommand.map { $0.args.description }.joined(separator: "\n")
                ) { onSaved in
                    saveCommands("after-startup-command", startupCommands, onSaved: onSaved)
                }
            }
        }
        .navigationTitle("Automation")
    }

    private func saveCommands(_ key: String, _ commands: String, onSaved: @escaping () -> Void) {
        persistSettingsConfig(section: nil, key: key, renderedValue: tomlStringArray(commands), model: model) {
            onSaved()
        }
    }

}
