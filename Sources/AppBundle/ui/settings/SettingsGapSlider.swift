import SwiftUI

struct SettingsGapSlider: View {
    let id: String
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let help: String
    let savedValue: Int
    let save: () -> Void
    @ObservedObject private var model = ShortcutSettingsModel.shared
    @FocusState private var numberFocused: Bool
    @State private var dragging = false
    @State private var maximum = 0
    @State private var lastSubmitted: Int?
    @State private var debounce: Task<Void, Never>?

    private var displayRange: ClosedRange<Double> {
        Double(min(range.lowerBound, savedValue))...Double(max(range.upperBound, max(maximum, value)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: $value, format: .number)
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 80, height: 28)
                    .focused($numberFocused).onSubmit(commit)
                    .accessibilityLabel(title + " value").accessibilityValue("\(value) points")
                    .accessibilityIdentifier(id + ".value")
                Text("pt").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Slider(value: Binding(get: { Double(value) }, set: { newValue in
                value = Int(newValue.rounded())
                if !dragging { scheduleKeyboardCommit() }
            }), in: displayRange, step: 1, onEditingChanged: { editing in
                dragging = editing
                debounce?.cancel()
                if !editing { commit() }
            })
            .accessibilityLabel(title).accessibilityValue("\(value) points")
            .accessibilityHint(help).accessibilityIdentifier(id)
            SettingsDescription(help)
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
        .onAppear { maximum = max(range.upperBound, value) }
        .onChange(of: numberFocused) { if !$0 { commit() } }
        .onDisappear { debounce?.cancel(); commit() }
    }

    private func scheduleKeyboardCommit() {
        debounce?.cancel()
        debounce = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        debounce?.cancel()
        guard value != savedValue else { return }
        value = max(0, value)
        maximum = max(maximum, value)
        guard value != savedValue, lastSubmitted != value || model.failedSettingID == id else { return }
        lastSubmitted = value
        model.activeSettingTitle = title
        save()
    }
}
