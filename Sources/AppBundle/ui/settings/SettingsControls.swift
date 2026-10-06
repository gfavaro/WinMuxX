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
        Section { content } header: { Text(title) }
    }
}

struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool
    var help: String? = nil
    let save: () -> Void

    init(_ title: String, isOn: Binding<Bool>, help: String? = nil, save: @escaping () -> Void) {
        self.title = title
        _isOn = isOn
        self.help = help
        self.save = save
    }
    var body: some View {
        Toggle(title, isOn: $isOn)
        .help(help ?? title)
        .modifier(SettingsFieldFeedback(title: title))
        .onChange(of: isOn) { _ in
            ShortcutSettingsModel.shared.activeSettingTitle = title
            save()
        }
    }
}

struct SettingsStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let help: String
    let unit: String
    let save: () -> Void
    init(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, help: String, unit: String = "pt", save: @escaping () -> Void) {
        self.title = title
        _value = value
        self.range = range
        self.help = help
        self.unit = unit
        self.save = save
    }
    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: $value, format: .number)
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 70)
                Text(unit).foregroundStyle(.secondary)
            }
        }
        .help(help)
        .modifier(SettingsFieldFeedback(title: title))
        .onChange(of: value) { newValue in
            let clamped = min(max(newValue, range.lowerBound), range.upperBound)
            if clamped != newValue {
                value = clamped
            } else {
                ShortcutSettingsModel.shared.activeSettingTitle = title
                save()
            }
        }
    }
}

struct SettingsDoubleStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let help: String
    let save: () -> Void

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: $value, format: .number)
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 70)
                Text("pt").foregroundStyle(.secondary)
            }
        }
        .help(help)
        .modifier(SettingsFieldFeedback(title: title))
        .onChange(of: value) { newValue in
            let clamped = min(max(newValue, range.lowerBound), range.upperBound)
            if clamped != newValue {
                value = clamped
            } else {
                ShortcutSettingsModel.shared.activeSettingTitle = title
                save()
            }
        }
    }
}

struct SettingsBorderColor: View {
    let title: String
    @Binding var text: String
    let save: () -> Void

    init(_ title: String, text: Binding<String>, save: @escaping () -> Void) {
        self.title = title
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
            SettingsTextField("Hex value", text: $text,
                              help: "Use #RRGGBB or #RRGGBBAA, including optional opacity.",
                              validate: settingsHexColorError, save: save)
        }
    }
}

struct SettingsTextField: View {
    @FocusState private var isFocused: Bool
    @State private var committedText: String?
    let title: String
    @Binding var text: String
    let help: String
    let validate: (String) -> String?
    let save: () -> Void

    init(_ title: String, text: Binding<String>, help: String,
         validate: @escaping (String) -> String? = { _ in nil }, save: @escaping () -> Void) {
        self.title = title
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
            if let error = validate(text) {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .modifier(SettingsFieldFeedback(title: title))
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
    @Binding var text: String
    let help: String
    let savedValue: String
    let save: (@escaping () -> Void) -> Void

    init(_ title: String, text: Binding<String>, help: String, savedValue: String, save: @escaping (@escaping () -> Void) -> Void) {
        self.title = title
        _text = text
        self.help = help
        self.save = save
        self.savedValue = savedValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
            Text(help).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 50)
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
            .controlSize(.small)
            .disabled(isSaving || savedText == text)
            if savedText != text {
                Text("Unsaved changes").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .modifier(SettingsFieldFeedback(title: title))
        .onAppear { savedText = savedValue }
    }
}

struct SettingsPicker<Selection: Hashable, Content: View>: View {
    let title: String; @Binding var selection: Selection; let help: String; @ViewBuilder let content: Content; let onChange: () -> Void
    init(_ title: String, selection: Binding<Selection>, help: String, @ViewBuilder content: () -> Content, onChange: @escaping () -> Void) { self.title = title; _selection = selection; self.help = help; self.content = content(); self.onChange = onChange }
    var body: some View {
        Picker(title, selection: $selection, content: { content })
            .help(help)
            .modifier(SettingsFieldFeedback(title: title))
            .onChange(of: selection) { _ in
                ShortcutSettingsModel.shared.activeSettingTitle = title
                onChange()
            }
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
                .font(.caption)
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
                .font(.caption)
                .foregroundStyle(.secondary)
            SettingsColorPresetPicker("Preset", selection: $selection,
                                      options: ChromeSolidColor.settingsPresets,
                                      title: { $0.title },
                                      colors: { [$0 == .custom ? Color(chromeHex: customColor) : $0.color] },
                                      colorWheelOption: .custom)
            if !ChromeSolidColor.settingsPresets.contains(selection) {
                Text("Current color: \(selection.title). Choose a preset or Custom to replace it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if selection == .custom {
                ColorPicker("Custom color", selection: Binding(
                    get: { Color(chromeHex: customColor) },
                    set: { customColor = $0.chromeHex },
                ), supportsOpacity: false)
            }
        }
        .padding(14)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 14)
        }
        .modifier(SettingsFieldFeedback(title: "Solid color"))
        .onChange(of: selection) { _ in
            ShortcutSettingsModel.shared.activeSettingTitle = "Solid color"
            onSelectionChange()
        }
        .onChange(of: customColor) { _ in
            guard selection == .custom else { return }
            ShortcutSettingsModel.shared.activeSettingTitle = "Solid color"
            onCustomColorChange()
        }
    }
}

private struct SettingsFieldFeedback: ViewModifier {
    let title: String
    @ObservedObject private var model = ShortcutSettingsModel.shared

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if model.failedSettingTitle == title, let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }
}
