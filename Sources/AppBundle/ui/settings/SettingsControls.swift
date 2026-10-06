import SwiftUI

struct SettingsScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        Form { content }
            .formStyle(.grouped)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        Section { content } header: { Text(title).accessibilityAddTraits(.isHeader) }
    }
}

struct SettingsToggle: View {
    let title: String
    let id: String
    @Binding var isOn: Bool
    var help: String? = nil
    let save: () -> Void

    init(_ title: String, id: String? = nil, isOn: Binding<Bool>, help: String? = nil, save: @escaping () -> Void) {
        self.title = title
        self.id = id ?? title
        _isOn = isOn
        self.help = help
        self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: Binding(get: { isOn }, set: { value in
                guard value != isOn else { return }
                isOn = value
                ShortcutSettingsModel.shared.activeSettingTitle = title
                save()
            }))
            .frame(minHeight: 28)
            .accessibilityIdentifier(id)
            .accessibilityHint(help ?? "")
            if let help { SettingsDescription(help) }
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
    }
}

struct SettingsDescription: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsStepper: View {
    let title: String
    let id: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let help: String
    let unit: String
    let save: () -> Void
    @FocusState private var focused: Bool
    @State private var submitted: Int?

    init(_ title: String, id: String? = nil, value: Binding<Int>, range: ClosedRange<Int>, help: String, unit: String = "pt", save: @escaping () -> Void) {
        self.title = title
        self.id = id ?? title
        _value = value
        self.range = range
        self.help = help
        self.unit = unit
        self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(title); Spacer(); editor }
                VStack(alignment: .leading) { Text(title); editor }
            }
            SettingsDescription(help)
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
        .onAppear { submitted = value }
        .onChange(of: focused) { if !$0 { commit() } }
        .onChange(of: value) { newValue in
            if !focused { submitted = newValue }
        }
    }

    private var editor: some View {
        HStack {
            TextField(title, value: $value, format: .number)
                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 80, height: 28)
                .focused($focused).onSubmit(commit)
                .accessibilityLabel(title).accessibilityValue("\(value) \(unit)")
                .accessibilityIdentifier(id + ".value")
            Text(unit).foregroundStyle(.secondary).accessibilityHidden(true)
            Stepper(title, value: Binding(get: { value }, set: { newValue in
                value = newValue
                commit(force: true)
            }), in: range).labelsHidden()
                .accessibilityLabel(title).accessibilityValue("\(value) \(unit)")
        }
    }

    private func commit() { commit(force: false) }
    private func commit(force: Bool) {
        guard force || submitted != value else { return }
        value = min(max(value, range.lowerBound), range.upperBound)
        submitted = value
        ShortcutSettingsModel.shared.activeSettingTitle = title
        save()
    }
}

struct SettingsDoubleStepper: View {
    let title: String
    var id: String = "borders.width"
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let help: String
    let save: () -> Void
    @FocusState private var focused: Bool
    @State private var submitted: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: $value, format: .number)
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 80, height: 28)
                    .focused($focused).onSubmit { commit() }
                    .accessibilityLabel(title).accessibilityValue("\(value) points")
                Text("pt").foregroundStyle(.secondary).accessibilityHidden(true)
                Stepper(title, value: Binding(get: { value }, set: { value = $0; commit() }), in: range, step: step)
                    .labelsHidden().accessibilityLabel(title)
            }
            SettingsDescription(help)
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
        .onAppear { submitted = value }
        .onChange(of: focused) { if !$0 { commit() } }
    }

    private func commit() {
        guard value.isFinite, submitted != value else { return }
        value = min(max(value, range.lowerBound), range.upperBound)
        submitted = value
        ShortcutSettingsModel.shared.activeSettingTitle = title
        save()
    }
}

struct SettingsBorderColor: View {
    let title: String
    let id: String
    @Binding var text: String
    let save: () -> Void

    init(_ title: String, id: String? = nil, text: Binding<String>, save: @escaping () -> Void) {
        self.title = title
        self.id = id ?? title
        _text = text
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ColorPicker(title, selection: Binding(
                get: {
                    let normalized = normalizedWindowBorderColor(text) ?? "#000000"
                    let value = UInt32(normalized.dropFirst(), radix: 16) ?? 0
                    let hasAlpha = normalized.count == 9
                    let rgb = hasAlpha ? value >> 8 : value
                    return Color(red: Double((rgb >> 16) & 255) / 255,
                                 green: Double((rgb >> 8) & 255) / 255,
                                 blue: Double(rgb & 255) / 255,
                                 opacity: hasAlpha ? Double(value & 255) / 255 : 1)
                },
                set: { color in
                    let components = NSColor(color).usingColorSpace(.sRGB) ?? .black
                    text = String(format: "#%02X%02X%02X%02X",
                                  Int((components.redComponent * 255).rounded()),
                                  Int((components.greenComponent * 255).rounded()),
                                  Int((components.blueComponent * 255).rounded()),
                                  Int((components.alphaComponent * 255).rounded()))
                    ShortcutSettingsModel.shared.activeSettingTitle = title
                    save()
                }
            ), supportsOpacity: true)
            SettingsTextField("Hex value", id: id, text: $text,
                              help: "Use #RRGGBB or #RRGGBBAA, including optional opacity.",
                              validate: settingsHexColorError, save: save)
        }
    }
}

struct SettingsTextField: View {
    @FocusState private var isFocused: Bool
    @State private var committedText: String?
    let title: String
    let id: String
    @Binding var text: String
    let help: String
    let validate: (String) -> String?
    let save: () -> Void

    init(_ title: String, id: String? = nil, text: Binding<String>, help: String,
         validate: @escaping (String) -> String? = { _ in nil }, save: @escaping () -> Void) {
        self.title = title
        self.id = id ?? title
        _text = text
        self.help = help
        self.validate = validate
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $text)
                .focused($isFocused)
                .onAppear { committedText = text }
                .onSubmit(commit)
                .onChange(of: isFocused) { focused in if !focused { commit() } }
                .onDisappear { commit() }
                .help(help)
                .accessibilityIdentifier(id)
                .accessibilityLabel(title)
            SettingsDescription(help)
            if let error = validate(text) {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
    }

    private func commit() {
        guard let committedText, committedText != text, validate(text) == nil else { return }
        self.committedText = text
        ShortcutSettingsModel.shared.activeSettingTitle = title
        save()
    }
}

func settingsHexColorError(_ text: String) -> String? {
    guard normalizedWindowBorderColor(text) != nil else {
        return "Use # followed by six or eight hexadecimal digits, for example #E1E3E4."
    }
    return nil
}

struct SettingsMultilineField: View {
    @State private var savedText: String?
    @State private var isSaving = false
    let title: String
    let id: String
    @Binding var text: String
    let help: String
    let savedValue: String
    let save: (@escaping () -> Void) -> Void

    init(_ title: String, id: String? = nil, text: Binding<String>, help: String, savedValue: String, save: @escaping (@escaping () -> Void) -> Void) {
        self.title = title
        self.id = id ?? title
        _text = text
        self.help = help
        self.save = save
        self.savedValue = savedValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
            SettingsDescription(help)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .accessibilityLabel(title).accessibilityHint(help)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
            Button(isSaving ? "Saving…" : "Save and apply") {
                let submittedText = text
                isSaving = true
                ShortcutSettingsModel.shared.activeSettingTitle = title
                save {
                    savedText = submittedText
                    isSaving = false
                }
            }
            .controlSize(.regular)
            .disabled(isSaving || savedText == text)
            if savedText != text {
                Text("Unsaved changes").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .modifier(SettingsFieldFeedback(id: id, title: title))
        .onAppear { savedText = savedValue }
        .onChange(of: savedValue) { savedText = $0; isSaving = false }
        .onReceive(ShortcutSettingsModel.shared.$failedSettingID) { failedID in
            if failedID == id { isSaving = false }
        }
    }
}

struct SettingsPicker<Selection: Hashable, Content: View>: View {
    let title: String
    let id: String
    @Binding var selection: Selection
    let help: String
    @ViewBuilder let content: Content
    let onChange: () -> Void
    init(_ title: String, id: String? = nil, selection: Binding<Selection>, help: String, @ViewBuilder content: () -> Content, onChange: @escaping () -> Void) {
        self.title = title; self.id = id ?? title; _selection = selection
        self.help = help; self.content = content(); self.onChange = onChange
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: Binding(get: { selection }, set: { value in
                guard value != selection else { return }
                selection = value
                ShortcutSettingsModel.shared.activeSettingTitle = title
                onChange()
            }), content: { content })
                .accessibilityIdentifier(id).accessibilityHint(help)
            if !help.isEmpty { SettingsDescription(help) }
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
    }
}

/// Circular swatches mirror System Settings while retaining every configured preset.
private struct SettingsColorPresetPicker<Option: Hashable & Identifiable>: View {
    let label: String
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    let colors: (Option) -> [Color]
    let colorWheelOption: Option?

    init(_ label: String, selection: Binding<Option>, options: [Option],
         title: @escaping (Option) -> String, colors: @escaping (Option) -> [Color],
         colorWheelOption: Option? = nil) {
        self.label = label
        _selection = selection
        self.options = options
        self.title = title
        self.colors = colors
        self.colorWheelOption = colorWheelOption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 32, maximum: 40), spacing: 10)], spacing: 10) {
                ForEach(options) { option in
                    Button { selection = option } label: {
                        Group {
                            if option == colorWheelOption {
                                AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                                center: .center)
                            } else {
                                LinearGradient(colors: colors(option), startPoint: .topLeading, endPoint: .bottomTrailing)
                            }
                        }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            .overlay { Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
                            .padding(4)
                            .overlay {
                                if selection == option {
                                    Circle().strokeBorder(.primary.opacity(0.6), lineWidth: 2)
                                }
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(title(option))
                    .accessibilityLabel(title(option))
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            Text(title(selection))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Selected color: \(title(selection))")
        }
    }
}

struct SettingsSolidColorPalette: View {
    @Binding var selection: ChromeSolidColor
    @Binding var customColor: String
    let isEnabled: Bool
    let onSelectionChange: () -> Void
    let onCustomColorChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Solid color")
            Text("Choose an opaque chrome color.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SettingsColorPresetPicker("Preset", selection: Binding(get: { selection }, set: { value in
                                          guard selection != value else { return }
                                          selection = value
                                          ShortcutSettingsModel.shared.activeSettingTitle = "Solid color"
                                          onSelectionChange()
                                      }),
                                      options: ChromeSolidColor.settingsPresets,
                                      title: { $0.title },
                                      colors: { [$0 == .custom ? Color(chromeHex: customColor) : $0.color] },
                                      colorWheelOption: .custom)
            if !ChromeSolidColor.settingsPresets.contains(selection) {
                Text("Current color: \(selection.title). Choose a preset or Custom to replace it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if selection == .custom {
                ColorPicker("Custom color", selection: Binding(
                    get: { Color(chromeHex: customColor) },
                    set: {
                        customColor = $0.chromeHex
                        ShortcutSettingsModel.shared.activeSettingTitle = "Custom color"
                        onCustomColorChange()
                    },
                ), supportsOpacity: false)
            }
        }
        .padding(14)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 14)
        }
        .modifier(SettingsFieldFeedback(id: "workspace-sidebar.solid-chrome-color", title: "Solid color"))
        .modifier(SettingsFieldFeedback(id: "workspace-sidebar.solid-chrome-custom-color", title: "Custom color"))

    }
}

struct SettingsFieldFeedback: ViewModifier {
    let id: String
    let title: String
    @ObservedObject private var model = ShortcutSettingsModel.shared

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if model.failedSettingID == id, let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).textSelection(.enabled)
                    .accessibilityLabel("Could not save \(title). \(error)")
            }
        }
    }
}
