import SwiftUI

/// One display's lone-window width: its own `[display."<selector>"] fullscreen-width`, or the
/// global width when switched off.
struct SettingsDisplayWidthRow: View {
    let row: SettingsDisplayRow
    var model: ShortcutSettingsModel
    @State private var hasOwnWidth = false
    @State private var percent = 100

    private var selector: String? { row.uuid.map { "uuid:" + $0 } ?? row.hardware }
    private var section: String? { selector.map { "display.\(settingsQuotedString($0))" } }

    var body: some View {
        if section != nil {
            VStack(alignment: .leading, spacing: 4) {
                SettingsToggle("Own lone-window width", id: "display.\(row.id).fullscreen-width.enabled", isOn: $hasOwnWidth,
                    help: "Use a different width for a lone tiled window or fullscreen on this display. Off follows the global width.") {
                    save(hasOwnWidth ? percent : nil)
                }
                if hasOwnWidth {
                    SettingsStepper("Width", id: "display.\(row.id).fullscreen-width", value: $percent, range: 10...100,
                        help: "Share of this display's available width.", unit: "%") {
                        save(percent)
                    }
                }
            }
            .onAppear(perform: load)
            .onChange(of: row.id) { load() }
        }
    }

    private func load() {
        let width = sortedMonitors.first { $0.displayUUID == row.uuid }
            .flatMap { matchingWindowSettings(config.displayWindowSettings, on: $0)?.fullscreenWidth }
        hasOwnWidth = width != nil
        percent = Int(((width ?? config.fullscreenWidth ?? 1.0) * 100).rounded())
    }

    private func save(_ percent: Int?) {
        guard let section else { return }
        let value = percent.map { String(format: "%.2f", Double($0) / 100) }
        persistSettingsConfigEdits([SettingsConfigEdit(section: section, key: "fullscreen-width", renderedValue: value)], model: model)
    }
}
