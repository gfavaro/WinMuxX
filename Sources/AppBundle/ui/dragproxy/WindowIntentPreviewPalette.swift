import AppKit
import SwiftUI

enum WindowIntentPreviewPalette {
    /// The drop preview's colour: the WinMuxX accent, as borders and tab pills use, or the
    /// solid chrome colour when the chrome is solid.
    @MainActor
    static func tint(style: ChromeStyle, solidColor: Color) -> Color {
        switch style {
            case .liquidGlass: Color(nsColor: winMuxAccentColor)
            case .solid: solidColor
        }
    }
}
