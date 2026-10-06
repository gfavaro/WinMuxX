import SwiftUI

struct ShortcutConfigurationReferenceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configuration Reference")
                    .font(.headline)
                Text("Use Configuration to edit the complete winmux.toml file. The settings panes cover the everyday options; this reference lists the remaining advanced sections.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ReferenceSection("Keyboard") {
                    ReferenceRow("[key-mapping]", "Keyboard layout preset and custom key notation mappings.")
                    ReferenceRow("[mode.<name>.binding]", "Chord and sequence shortcuts for any mode.")
                    ReferenceRow("[mode.<name>.binding-tap]", "Tap-only shortcut bindings.")
                }
                ReferenceSection("Rules and integrations") {
                    ReferenceRow("[exec]", "Inherited environment and explicit environment variables for commands.")
                    ReferenceRow("[workspace-to-monitor-force-assignment]", "Workspace-to-display assignments.")
                    ReferenceRow("on-window-detected", "Window matching rules and commands to run.")
                    ReferenceRow("on-focus-changed", "Commands that run after the focused window changes.")
                    ReferenceRow("on-focused-monitor-changed", "Commands that run after the active display changes.")
                    ReferenceRow("on-mode-changed", "Commands that run after switching modes.")
                }
                ReferenceSection("Named sidebar items") {
                    ReferenceRow("workspace-labels", "Override visible workspace names.")
                    ReferenceRow("project-labels", "Override visible project names.")
                    ReferenceRow("project-colors", "Assign project colors using #RRGGBB values.")
                }
                Text("The Configuration editor validates the entire file before saving and shows parser errors inline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

private struct ReferenceSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content
        }
    }
}

private struct ReferenceRow: View {
    let key: String
    let description: String

    init(_ key: String, _ description: String) {
        self.key = key
        self.description = description
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                keyLabel.fixedSize()
                descriptionLabel
            }
            VStack(alignment: .leading, spacing: 6) {
                keyLabel
                descriptionLabel
            }
        }
    }

    private var keyLabel: some View {
        Text(key).font(.system(.body, design: .monospaced))
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
    private var descriptionLabel: some View {
        Text(description).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
