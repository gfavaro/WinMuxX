import SwiftUI

struct SettingsConfigurationView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var showsReference = false
    var body: some View {
        VStack(spacing: 12) {
            Picker("Configuration section", selection: $showsReference) {
                Text("Editor").tag(false)
                Text("Reference").tag(true)
            }
            .pickerStyle(.segmented).padding(.horizontal, 20)
            if showsReference { ShortcutConfigurationReferenceView() }
            else { ShortcutAdvancedView(model: model) }
        }
    }
}
