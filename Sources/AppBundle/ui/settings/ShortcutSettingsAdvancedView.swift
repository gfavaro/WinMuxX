import AppKit
import Common
import MASShortcut
import SwiftUI

struct ShortcutAdvancedView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var configText = ""
    @State private var validationMessage: String? = nil
    @State private var saveMessage: String? = nil
    @State private var targetUrl: URL? = nil
    @State private var hasLoaded = false
    @State private var savedText = ""
    @State private var diskTextAtLoad: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Config Editor")
                        .font(.headline)
                    if let targetUrl {
                        Text(targetUrl.path)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                Button("Reload From Disk") {
                    loadFromDisk()
                }
                .controlSize(.regular)
                Button("Validate") {
                    validateConfig()
                }
                .controlSize(.regular)
                Button(isSaving ? "Saving…" : "Save and apply") {
                    saveConfig()
                }
                .controlSize(.regular)
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(isSaving || configText == savedText)
            }

            if let validationMessage {
                Text(validationMessage)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.red)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.06))
                    .textSelection(.enabled)
            } else if let saveMessage {
                Text(saveMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }

            if configText != savedText {
                Text("Unsaved changes").font(.callout).foregroundStyle(.secondary)
            }

            TextEditor(text: $configText)
                .accessibilityLabel("TOML configuration editor")
                .accessibilityHint("Edit the complete configuration. Use Validate before Save and apply.")
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
        .padding(18)
        .onChange(of: model.settingsRevision) { _ in
            if configText == savedText { loadFromDisk(preservingDraft: true) }
        }
        .onChange(of: configText) { model.configurationDraft = $0 == savedText ? nil : RawConfigDraft(text: $0, baseline: diskTextAtLoad) }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            loadFromDisk(preservingDraft: true)
        }
    }

    private func loadFromDisk(preservingDraft: Bool = false) {
        let resolvedUrl = advancedConfigEditorTargetUrl()
        targetUrl = resolvedUrl
        validationMessage = nil
        saveMessage = nil
        do {
            diskTextAtLoad = try ConfigFileStore.read(resolvedUrl)
            configText = diskTextAtLoad ?? starterConfigText()
        } catch {
            validationMessage = error.localizedDescription
            return
        }
        savedText = configText
        if preservingDraft, let draft = model.configurationDraft {
            configText = draft.text
            diskTextAtLoad = draft.baseline
        }
        else { model.configurationDraft = nil }
    }

    private func validateConfig() {
        saveMessage = nil
        let parsed = parseConfig(configText)
        if parsed.errors.isEmpty {
            validationMessage = nil
            saveMessage = "Config is valid."
        } else {
            validationMessage = parsed.errors.map(\.description).joined(separator: "\n\n")
        }
    }

    private func saveConfig() {
        model.errorMessage = nil
        saveMessage = nil
        let parsed = parseConfig(configText)
        if !parsed.errors.isEmpty {
            validationMessage = parsed.errors.map(\.description).joined(separator: "\n\n")
            return
        }
        validationMessage = nil
        let resolvedUrl = targetUrl ?? advancedConfigEditorTargetUrl()
        targetUrl = resolvedUrl

        let submittedText = configText
        let expectedDiskText = diskTextAtLoad
        isSaving = true
        model.saveQueue.enqueue {
            model.savingSettingIDs.insert("configuration")
            defer {
                isSaving = false
                model.savingSettingIDs.remove("configuration")
            }
            do {
                try ConfigFileStore.replace(at: resolvedUrl, text: submittedText, expected: expectedDiskText)
                diskTextAtLoad = submittedText
                let isOk = try await model.configAccess.reload(resolvedUrl)
                if isOk {
                    savedText = submittedText
                    if configText == submittedText { model.configurationDraft = nil }
                    saveMessage = "Saved and applied."
                    model.reload()
                } else {
                    saveMessage = nil
                    validationMessage = "Saved, but reload failed. Check the parser error message window."
                }
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
private func advancedConfigEditorTargetUrl() -> URL {
    preferredEditableConfigUrl()
}


@MainActor
func shortcutSettingsWindow() -> NSWindow? {
    NSApplication.shared.windows.first { $0.identifier?.rawValue == shortcutSettingsWindowId }
}

@MainActor
func presentShortcutSettingsWindow(_ window: NSWindow) {
    window.styleMask.insert(.resizable)
    window.contentMinSize = NSSize(width: settingsWindowWidth, height: settingsWindowMinimumHeight)
    window.contentMaxSize = NSSize(width: settingsWindowWidth, height: .greatestFiniteMagnitude)
    if abs(window.contentLayoutRect.width - settingsWindowWidth) > 1 {
        window.setContentSize(NSSize(width: settingsWindowWidth,
                                    height: max(settingsWindowMinimumHeight, window.contentLayoutRect.height)))
    }
    NSApp.activate(ignoringOtherApps: true)
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}
