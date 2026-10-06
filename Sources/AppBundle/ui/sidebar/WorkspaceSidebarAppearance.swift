import AppKit
import SwiftUI

/// SwiftUI supplies interpolated widths during expansion/collapse, including
/// Reduce Motion. This keeps the native material in step without a timer.
struct WorkspaceSidebarMaterialGeometry: NSViewRepresentable, Animatable {
    let configuration: WorkspaceSidebarConfiguration
    let wallpaperTone: WorkspaceSidebarWallpaperTone?
    let contentColorScheme: ColorScheme
    nonisolated var visibleWidth: CGFloat
    nonisolated var animatableData: CGFloat {
        get { visibleWidth }
        set { visibleWidth = newValue }
    }

    func makeNSView(context: Context) -> WorkspaceSidebarMaterialGeometryView {
        WorkspaceSidebarMaterialGeometryView()
    }

    func updateNSView(_ view: WorkspaceSidebarMaterialGeometryView, context: Context) {
        view.configuration = configuration
        view.visibleWidth = visibleWidth
        view.wallpaperTone = wallpaperTone
        view.contentColorScheme = contentColorScheme
        view.updateMaterial()
    }
}

final class WorkspaceSidebarMaterialGeometryView: NSView {
    var configuration = WorkspaceSidebarConfiguration.empty
    var visibleWidth: CGFloat = 0
    var wallpaperTone: WorkspaceSidebarWallpaperTone?
    var contentColorScheme: ColorScheme = .dark
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMaterial()
    }

    func updateMaterial() {
        (window as? WorkspaceSidebarPanel)?.materialContainer.configure(
            configuration: configuration, visibleWidth: visibleWidth, wallpaperTone: wallpaperTone,
            contentColorScheme: contentColorScheme
        )
    }
}

struct WorkspaceSidebarLabel: View {
    @Environment(\.workspaceSidebarAppearance) private var appearance
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.workspaceSidebarPreviewAccessibility) private var previewAccessibility
    let text: String
    var size: CGFloat = 15
    var weight: NSFont.Weight = .regular
    var secondary = false
    var monospacedDigit = false
    var alignment: NSTextAlignment = .left
    var customColor: Color = .primary

    var body: some View {
        if appearance == .system {
            WorkspaceSidebarNativeLabel(text: text, size: size, weight: weight,
                secondary: secondary && contrast != .increased && !previewAccessibility.increasedContrast,
                monospacedDigit: monospacedDigit, alignment: alignment)
                .allowsHitTesting(false)
        } else {
            Text(text)
                .font(.system(size: size, weight: weight == .bold ? .bold : weight == .semibold ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(customColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct WorkspaceSidebarNativeLabel: NSViewRepresentable {
    let text: String
    let size: CGFloat
    let weight: NSFont.Weight
    var secondary = false
    var monospacedDigit = false
    var alignment: NSTextAlignment = .left

    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configure(label)
        return label
    }

    func updateNSView(_ label: NSTextField, context: Context) { configure(label) }

    func configure(_ label: NSTextField) {
        label.stringValue = text
        label.font = monospacedDigit ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.alignment = alignment
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? intrinsic.width, intrinsic.width), height: intrinsic.height)
    }
}

private struct WorkspaceSidebarAppearanceKey: EnvironmentKey {
    static let defaultValue: WorkspaceSidebarAppearance = .custom
}

private struct WorkspaceSidebarWallpaperSampleKey: EnvironmentKey {
    static let defaultValue: WorkspaceSidebarWallpaperSample? = nil
}

/// Only deterministic developer previews set these; production uses system preferences.
struct WorkspaceSidebarPreviewAccessibility: Sendable {
    var reduceTransparency = false
    var increasedContrast = false
}

private struct WorkspaceSidebarPreviewAccessibilityKey: EnvironmentKey {
    static let defaultValue = WorkspaceSidebarPreviewAccessibility()
}

extension EnvironmentValues {
    var workspaceSidebarWallpaperSample: WorkspaceSidebarWallpaperSample? {
        get { self[WorkspaceSidebarWallpaperSampleKey.self] }
        set { self[WorkspaceSidebarWallpaperSampleKey.self] = newValue }
    }
    var workspaceSidebarPreviewAccessibility: WorkspaceSidebarPreviewAccessibility {
        get { self[WorkspaceSidebarPreviewAccessibilityKey.self] }
        set { self[WorkspaceSidebarPreviewAccessibilityKey.self] = newValue }
    }

    var workspaceSidebarAppearance: WorkspaceSidebarAppearance {
        get { self[WorkspaceSidebarAppearanceKey.self] }
        set { self[WorkspaceSidebarAppearanceKey.self] = newValue }
    }
}

/// Kept local to sidebar descendants; shared tab/switcher chrome is not affected.
@propertyWrapper
struct SidebarColors: DynamicProperty {
    @Environment(\.workspaceSidebarAppearance) var appearance
    @Environment(\.colorSchemeContrast) var contrast
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.workspaceSidebarPreviewAccessibility) var previewAccessibility

    var wrappedValue: WorkspaceSidebarPalette {
        // Also redraw AppKit-generated menu swatches when the system theme changes.
        _ = colorScheme
        return WorkspaceSidebarPalette(appearance: appearance, increasedContrast: contrast == .increased || previewAccessibility.increasedContrast, colorScheme: colorScheme)
    }
}

struct WorkspaceSidebarPalette {
    let appearance: WorkspaceSidebarAppearance
    var increasedContrast = false
    var colorScheme: ColorScheme = .dark

    var foreground: Color {
        appearance == .custom ? (colorScheme == .light ? .black : .white) : Color(nsColor: .labelColor)
    }
    var separator: Color {
        appearance == .system
            ? Color(nsColor: .separatorColor).opacity(increasedContrast ? 1 : 0.7)
            : foreground.opacity(GlassToken.separatorOpacity)
    }

    func text(opacity: Double) -> Color {
        guard opacity > 0 else { return .clear }
        return foreground.opacity(increasedContrast ? 1 : opacity)
    }
}

enum WorkspaceSidebarSystemBackground {
    case opaque, clear, glass, frosted

    static func resolve(showBackground: Bool, reduceTransparency: Bool, expanded: Bool = false) -> Self {
        if reduceTransparency { return .opaque }
        if expanded { return .frosted }
        return showBackground ? .glass : .clear
    }
}

struct WorkspaceSidebarSystemSurface: View {
    var expanded = false
    var menuBarBackground = false
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.workspaceSidebarPreviewAccessibility) var previewAccessibility

    var body: some View {
        switch WorkspaceSidebarSystemBackground.resolve(
            showBackground: menuBarBackground,
            reduceTransparency: reduceTransparency || previewAccessibility.reduceTransparency,
            expanded: expanded
        ) {
        case .opaque:
            Color(nsColor: .windowBackgroundColor)
        case .clear:
            Color.clear
        case .frosted:
            WorkspaceSidebarFrostedSurface()
        case .glass:
            if #available(macOS 26, *) {
                WorkspaceSidebarNativeGlass()
            } else {
                WorkspaceSidebarVisualEffect(background: .menuBar)
            }
        }
    }
}

@available(macOS 26, *)
private struct WorkspaceSidebarNativeGlass: NSViewRepresentable {

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSGlassEffectView) {
        view.style = .regular
        // The outer sidebar shape owns rounding: compact stays square.
        view.cornerRadius = 0
        view.tintColor = nil
        view.appearance = nil
    }
}

struct WorkspaceSidebarVisualEffect: NSViewRepresentable {
    var background: WorkspaceSidebarBackground = .sidebar
    var frosted = false
    @Environment(\.colorScheme) var colorScheme
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    func configure(_ view: NSVisualEffectView) {
        view.material = frosted ? .hudWindow : .sidebar
        // Keep the expanded transparent sidebar visibly translucent rather than the
        // near-opaque header material, while retaining the native behind-window blur.
        view.alphaValue = frosted ? 0.93 : 1
        view.blendingMode = .behindWindow
        // The sidebar stays visible when another application's window has focus.
        view.state = .active
        view.isEmphasized = false
        view.appearance = frosted ? NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) : nil
    }
}

struct WorkspaceSidebarFrostedSurface: View {
    var tint: WorkspaceSidebarFrostedTint = .automatic
    @Environment(\.workspaceSidebarWallpaperSample) var wallpaperSample
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.workspaceSidebarPreviewAccessibility) var previewAccessibility

    var body: some View {
        if reduceTransparency || previewAccessibility.reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            ZStack {
                WorkspaceSidebarVisualEffect(frosted: true)
                WorkspaceSidebarFrostedVeil(tint: tint)
            }
        }
    }

    var resolvedColors: [Color] {
        tint.colors(colorScheme: colorScheme, wallpaperSample: wallpaperSample)
    }
}

/// A tint only: the panel already owns the single native blur surface.
struct WorkspaceSidebarFrostedVeil: View {
    var tint: WorkspaceSidebarFrostedTint = .automatic
    @Environment(\.workspaceSidebarWallpaperSample) private var wallpaperSample
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.workspaceSidebarPreviewAccessibility) private var previewAccessibility

    var body: some View {
        if !reduceTransparency && !previewAccessibility.reduceTransparency {
            LinearGradient(colors: tint.colors(colorScheme: colorScheme, wallpaperSample: wallpaperSample),
                startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(workspaceSidebarFrostedVeilOpacity(tint: tint, hasWallpaperSample: wallpaperSample != nil))
                .allowsHitTesting(false)
        }
    }
}

func workspaceSidebarFrostedVeilOpacity(tint: WorkspaceSidebarFrostedTint, hasWallpaperSample: Bool) -> Double {
    tint == .automatic && !hasWallpaperSample ? 0.14 : 0.36
}

extension WorkspaceSidebarFrostedTint {
    var preferredColorScheme: ColorScheme? {
        switch self {
            case .automatic: nil
            case .white, .cyan, .pink, .ice: .light
            case .black, .indigo, .purple, .aurora: .dark
        }
    }

    func colors(colorScheme: ColorScheme, wallpaperSample: WorkspaceSidebarWallpaperSample? = nil) -> [Color] {
        if self == .automatic, let wallpaperSample { return [wallpaperSample.color] }
        return switch self {
            case .automatic: [colorScheme == .dark ? .black : .white]
            case .white: [.white]
            case .black: [.black]
            case .cyan: [.cyan]
            case .pink: [.pink]
            case .indigo: [.indigo]
            case .purple: [.purple]
            case .ice: [.white, .cyan, .pink]
            case .aurora: [.black, .indigo, .purple]
        }
    }
}

struct WorkspaceSidebarColorScheme: ViewModifier {
    let appearance: WorkspaceSidebarAppearance
    var solidColorScheme: ColorScheme = .dark
    @Environment(\.colorScheme) var systemColorScheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, appearance == .custom ? solidColorScheme : systemColorScheme)
    }
}

/// Chooses the higher-contrast foreground for an opaque sidebar color.
func workspaceSidebarSolidColorScheme(_ color: Color) -> ColorScheme {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return .dark }
    func linear(_ component: CGFloat) -> Double {
        let value = Double(component)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    return luminance > 0.179 ? .light : .dark
}
