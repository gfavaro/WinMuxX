import AppKit
import Common
import TOMLKit

enum WindowBorderOrder: String { case below, above }

struct WindowBordersConfig: ConvenienceCopyable, Equatable {
    var enabled = true
    var width = 4.0
    var activeColor = windowBorderAccentColor
    var inactiveColor = "#00000000"
    var order = WindowBorderOrder.below
    var excludeApps: [String] = []
}

private let borderParsers: [String: any ParserProtocol<WindowBordersConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "width": Parser(\.width) { raw, trace in
        let value = raw.double ?? raw.int.map(Double.init)
        return value.orFailure(.semantic(trace, "Must be a finite, nonnegative number"))
            .filter(.semantic(trace, "Must be a finite, nonnegative number")) { $0.isFinite && $0 >= 0 }
    },
    "order": Parser(\.order) { raw, trace in
        parseString(raw, trace).flatMap { WindowBorderOrder(rawValue: $0).orFailure(.semantic(trace, "Must be 'below' or 'above'")) }
    },
    "exclude-apps": Parser(\.excludeApps, parseArrayOfStrings),
    "active-color": Parser(\.activeColor, parseBorderColor),
    "inactive-color": Parser(\.inactiveColor, parseBorderColor),
]

private func parseBorderColor(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<String> {
    parseString(raw, trace).flatMap {
        normalizedWindowBorderColor($0).orFailure(.semantic(trace, "Use 'accent', #RRGGBB or #RRGGBBAA"))
    }
}

/// The system accent color: a mid-tone, so the border stays visible on light and dark windows.
let windowBorderAccentColor = "accent"

func normalizedWindowBorderColor(_ raw: String) -> String? {
    if raw.lowercased() == windowBorderAccentColor { return windowBorderAccentColor }
    guard raw.hasPrefix("#"), [7, 9].contains(raw.count), UInt32(raw.dropFirst(), radix: 16) != nil else { return nil }
    return raw.uppercased()
}

/// A border color as 0xRRGGBBAA. `accent` resolves the system accent color in the current
/// appearance; graphite draws blue, as elsewhere, so focus stays distinct from gray borders.
@MainActor
func windowBorderRGBA(_ color: String) -> UInt32 {
    guard color == windowBorderAccentColor else { return windowBorderHexRGBA(color) }
    let accent: NSColor = NSColor.currentControlTint == .graphiteControlTint ? .systemBlue : .controlAccentColor
    var resolved: NSColor?
    // NSApp is nil before the application starts, as in unit tests.
    (NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance { resolved = accent.usingColorSpace(.sRGB) }
    guard let resolved else { return 0x007A_FFFF }
    return [resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent]
        .reduce(0) { ($0 << 8) | UInt32((min(max($1, 0), 1) * 255).rounded()) }
}

/// `#RRGGBB` or `#RRGGBBAA` as 0xRRGGBBAA; six digits are opaque.
func windowBorderHexRGBA(_ hex: String) -> UInt32 {
    let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
    let hasAlpha = hex.count == 9
    return hasAlpha ? value : (value << 8) | 255
}

func parseWindowBorders(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace, _ errors: inout [TomlParseError]) -> WindowBordersConfig {
    parseTable(raw, WindowBordersConfig(), borderParsers, trace, &errors)
}
