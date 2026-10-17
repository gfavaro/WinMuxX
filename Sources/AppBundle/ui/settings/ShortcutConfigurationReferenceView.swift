import AppKit
import SwiftUI

struct ShortcutConfigurationReferenceView: View {
    var onNavigate: (SettingsSidebarItem) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Configuration Reference").font(.title2.bold())
                Text("Edit the complete winmux.toml file in Configuration → Editor. Examples are independent snippets: merge them into existing sections instead of adding duplicate tables or keys. Defaults below come from the app’s default configuration, not your current settings.")
                    .foregroundStyle(.secondary)
                ForEach(configurationReferenceSections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(section.title).font(.headline)
                            Spacer()
                            if let pane = section.pane {
                                Button("Open \(pane.label)") { onNavigate(pane) }
                            }
                        }
                        Text(section.description).foregroundStyle(.secondary)
                        if let defaults = section.defaults {
                            Text("Defaults: \(defaults)").font(.callout)
                                .textSelection(.enabled)
                        }
                        if let example = section.example {
                            HStack {
                                Text("Example").font(.subheadline.bold())
                                Spacer()
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(example, forType: .string)
                                }
                                .accessibilityLabel("Copy \(section.title) example")
                            }
                            Text(example).font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Divider()
                }
                Text("The Editor validates the entire file before saving. Changes apply after a successful reload. A TOML key belongs to the most recent table header; put root-level options before the first table.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}
