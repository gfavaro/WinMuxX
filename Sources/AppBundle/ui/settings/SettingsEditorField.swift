import SwiftUI

/// Keep the field's label visible independently of its placeholder.
struct SettingsEditorField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    init(_ title: String, prompt: String, text: Binding<String>) {
        self.title = title; self.prompt = prompt; self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden().textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel(title)
        }
    }
}
