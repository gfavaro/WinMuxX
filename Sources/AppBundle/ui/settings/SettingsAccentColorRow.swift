import AppKit
import SwiftUI

/// The root `accent-color`: the system accent until a color is chosen.
struct SettingsAccentColorRow: View {
    var model: ShortcutSettingsModel
    @SettingsDraft("accent-color", load: { config.accentColor ?? "" }) private var hex: String
    @State private var pendingSave: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsToggle("Use system accent color", id: "accent-color", isOn: Binding(
                get: { hex.isEmpty },
                set: { hex = $0 ? "" : "#" + (NSColor.controlAccentColor.hexRGB) }),
                help: "Window borders, the active tab, the hover bar, the overview and mode indicators follow the macOS accent color.") {
                save()
            }
            if !hex.isEmpty {
                ColorPicker("Accent color", selection: Binding(
                    get: { Color(nsColor: NSColor(hexRGB: hex) ?? .controlAccentColor) },
                    set: { color in
                        hex = "#" + NSColor(color).hexRGB
                        ShortcutSettingsModel.shared.activeSettingTitle = "Accent color"
                        // The color panel reports every step of a drag; write once it settles.
                        pendingSave?.cancel()
                        pendingSave = Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            guard !Task.isCancelled else { return }
                            save()
                        }
                    }), supportsOpacity: false)
            }
        }
    }

    private func save() {
        persistSettingsConfigEdits([SettingsConfigEdit(section: nil, key: "accent-color", renderedValue: hex.isEmpty ? nil : "'\(hex)'")], model: model)
    }
}

private extension NSColor {
    convenience init?(hexRGB: String) {
        guard hexRGB.count == 7, let value = UInt32(hexRGB.dropFirst(), radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    var hexRGB: String {
        let c = usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
