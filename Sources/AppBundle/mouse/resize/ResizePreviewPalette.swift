import AppKit
import SwiftUI

/// A resolved snapshot, recreated at presentation/appearance boundaries. CGColors
/// are never static: CALayer cannot automatically resolve dynamic NSColors.
struct ResizePreviewPalette {
    let fill: CGColor
    let stroke: CGColor
    let tabGroupBar: CGColor
    let fallbackIconFill: CGColor
    let sourceFrameFill: CGColor
    let sourceFrameStroke: CGColor
    let sourceMockTabFill: CGColor
    let sourceMockTabStroke: CGColor

    init(appearance: ResolvedChromeAppearance, increasedContrast: Bool) {
        let foreground: NSColor = appearance.scheme == .dark ? .white : .black
        let background: NSColor = appearance.fill.map(NSColor.init) ??
            (appearance.scheme == .dark ? NSColor(calibratedWhite: 0.10, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1))
        func ink(_ opacity: CGFloat) -> CGColor {
            foreground.withAlphaComponent(increasedContrast ? max(opacity, 0.35) : opacity).cgColor
        }
        fill = background.cgColor
        stroke = ink(0.12)
        tabGroupBar = ink(0.055)
        fallbackIconFill = ink(0.12)
        sourceFrameFill = background.cgColor
        sourceFrameStroke = ink(0.12)
        sourceMockTabFill = ink(0.085)
        sourceMockTabStroke = ink(0.12)
    }
}
