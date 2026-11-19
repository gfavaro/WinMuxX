import AppKit
import SwiftUI
@testable import AppBundle

/// The kinds of app window a scene can show. Each is drawn in code with made-up content, so a
/// picture never carries another app's interface, a website or anyone's documents.
enum MarketingAppKind {
    case editor, browser, notes, terminal
}

private enum MarketingPalette {
    static let windowDark = Color(red: 0.11, green: 0.115, blue: 0.135)
    static let windowLight = Color(red: 0.97, green: 0.97, blue: 0.975)
    static let titleBarDark = Color(red: 0.15, green: 0.155, blue: 0.18)
    static let titleBarLight = Color(red: 0.92, green: 0.92, blue: 0.93)
    static let keyword = Color(red: 0.98, green: 0.45, blue: 0.62)
    static let type = Color(red: 0.45, green: 0.80, blue: 0.95)
    static let string = Color(red: 0.98, green: 0.64, blue: 0.40)
    static let comment = Color(white: 0.48)
    static let plain = Color(white: 0.86)
}

/// One app window: its own title bar with the traffic lights, then content for its kind.
struct MarketingAppWindow: View {
    let kind: MarketingAppKind
    var title: String = ""
    var cornerRadius: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            // Content never sizes the window: the tile does, and whatever does not fit is cut off.
            Color.clear
                .overlay(alignment: .topLeading) { content }
                .clipped()
        }
        .background(isLight ? MarketingPalette.windowLight : MarketingPalette.windowDark)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(isLight ? 0.5 : 0.12), lineWidth: 0.6)
        }
    }

    private var isLight: Bool { kind == .browser || kind == .notes }

    private var titleBar: some View {
        HStack(spacing: 8) {
            ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                     Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { color in
                Circle().fill(color).frame(width: 12, height: 12)
            }
            Spacer(minLength: 12)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isLight ? Color.black.opacity(0.7) : Color.white.opacity(0.75))
                .lineLimit(1)
            Spacer(minLength: 12)
            Color.clear.frame(width: 52, height: 1)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(isLight ? MarketingPalette.titleBarLight : MarketingPalette.titleBarDark)
    }

    @ViewBuilder private var content: some View {
        switch kind {
            case .editor: MarketingEditorContent()
            case .browser: MarketingBrowserContent()
            case .notes: MarketingNotesContent()
            case .terminal: MarketingTerminalContent()
        }
    }
}

private struct MarketingEditorContent: View {
    private typealias Token = (String, Color)
    private let files = ["Package.swift", "Sources", "  App.swift", "  Layout.swift", "  Sidebar.swift", "Tests", "  LayoutTests.swift", "README.md"]
    private let lines: [[Token]] = [
        [("import", MarketingPalette.keyword), (" SwiftUI", MarketingPalette.plain)],
        [],
        [("/// Splits the space between two panes.", MarketingPalette.comment)],
        [("struct", MarketingPalette.keyword), (" SplitLayout", MarketingPalette.type), (": ", MarketingPalette.plain), ("Layout", MarketingPalette.type), (" {", MarketingPalette.plain)],
        [("    var", MarketingPalette.keyword), (" ratio: ", MarketingPalette.plain), ("CGFloat", MarketingPalette.type), (" = 0.5", MarketingPalette.plain)],
        [],
        [("    func", MarketingPalette.keyword), (" placeSubviews(in bounds: ", MarketingPalette.plain), ("CGRect", MarketingPalette.type), (") {", MarketingPalette.plain)],
        [("        let", MarketingPalette.keyword), (" first = bounds.width * ratio", MarketingPalette.plain)],
        [("        let", MarketingPalette.keyword), (" gap: ", MarketingPalette.plain), ("CGFloat", MarketingPalette.type), (" = 8", MarketingPalette.plain)],
        [("        // Leading pane, then the rest after the gap.", MarketingPalette.comment)],
        [("        place", MarketingPalette.plain), ("(\"leading\"", MarketingPalette.string), (", width: first)", MarketingPalette.plain)],
        [("        place", MarketingPalette.plain), ("(\"trailing\"", MarketingPalette.string), (", width: bounds.width - first - gap)", MarketingPalette.plain)],
        [("    }", MarketingPalette.plain)],
        [("}", MarketingPalette.plain)],
        [],
        [("#Preview", MarketingPalette.keyword), (" {", MarketingPalette.plain)],
        [("    SplitLayout", MarketingPalette.type), ("(ratio: 0.6)", MarketingPalette.plain)],
        [("}", MarketingPalette.plain)],
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                    Text(file)
                        .font(.system(size: 11.5))
                        .foregroundStyle(index == 3 ? Color.white : Color.white.opacity(0.55))
                        .padding(.vertical, 2).padding(.horizontal, 6)
                        .background(index == 3 ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 150, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.18))

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, tokens in
                    HStack(spacing: 14) {
                        Text("\(index + 1)").foregroundStyle(Color.white.opacity(0.28)).frame(width: 20, alignment: .trailing)
                        tokens.reduce(Text("")) { $0 + Text($1.0).foregroundColor($1.1) }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct MarketingBrowserContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left"); Image(systemName: "chevron.right")
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text("fieldnotes.example")
                }
                .font(.system(size: 12))
                .padding(.horizontal, 14).frame(height: 26)
                .background(Color.black.opacity(0.06), in: Capsule())
                Spacer()
                Image(systemName: "square.and.arrow.up")
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.black.opacity(0.5))
            .padding(.horizontal, 14).frame(height: 40)

            VStack(alignment: .leading, spacing: 14) {
                Text("Field Notes").font(.system(size: 30, weight: .bold, design: .serif)).foregroundStyle(.black.opacity(0.85))
                Text("Small tools for focused work").font(.system(size: 15)).foregroundStyle(.black.opacity(0.5))
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.70, blue: 0.95), Color(red: 0.80, green: 0.62, blue: 0.92)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 150)
                ForEach([1.0, 0.92, 0.97, 0.6], id: \.self) { width in
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.10)).frame(width: proxy.size.width * width, height: 9)
                    }
                    .frame(height: 9)
                }
                HStack(spacing: 12) {
                    ForEach([Color(red: 0.95, green: 0.78, blue: 0.55), Color(red: 0.62, green: 0.85, blue: 0.72), Color(red: 0.72, green: 0.78, blue: 0.95)], id: \.self) {
                        RoundedRectangle(cornerRadius: 10).fill($0).frame(height: 90)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 18)
        }
    }
}

private struct MarketingNotesContent: View {
    private let notes = [("Weekly plan", "Mon"), ("Reading list", "Sun"), ("Ideas", "Sat"), ("Trip checklist", "Fri"), ("Recipes", "Thu")]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.0).font(.system(size: 12.5, weight: .semibold))
                        Text(note.1).font(.system(size: 11)).foregroundStyle(.black.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(index == 0 ? Color(red: 1, green: 0.83, blue: 0.3).opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                Spacer()
            }
            .foregroundStyle(.black.opacity(0.82))
            .padding(10)
            .frame(width: 170)
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.035))

            VStack(alignment: .leading, spacing: 10) {
                Text("Weekly plan").font(.system(size: 20, weight: .bold))
                ForEach(["Review the layout draft", "Write release notes", "Call about the venue", "Water the plants"], id: \.self) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.hasPrefix("Write") ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.hasPrefix("Write") ? Color.orange : Color.black.opacity(0.3))
                        Text(item).font(.system(size: 13.5))
                    }
                }
            }
            .foregroundStyle(.black.opacity(0.82))
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct MarketingTerminalContent: View {
    private let lines: [(String, Color)] = [
        ("~/projects/fieldnotes $ swift build", .white),
        ("Building for debugging...", Color.white.opacity(0.6)),
        ("Build complete! (4.21s)", Color(red: 0.45, green: 0.85, blue: 0.5)),
        ("~/projects/fieldnotes $ swift test", .white),
        ("Test Suite 'All tests' started", Color.white.opacity(0.6)),
        ("Executed 128 tests, with 0 failures", Color(red: 0.45, green: 0.85, blue: 0.5)),
        ("~/projects/fieldnotes $ git status --short", .white),
        (" M Sources/Layout.swift", Color(red: 0.95, green: 0.75, blue: 0.4)),
        ("~/projects/fieldnotes $ ", .white),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.0).foregroundStyle(line.1)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(1)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.075, blue: 0.09))
    }
}

/// A tab group as WinMuxX draws it: the production tab bar and frame around the active window.
struct MarketingTabGroupWindow: View {
    let strip: WindowTabStripViewModel
    let kind: MarketingAppKind
    let title: String

    var body: some View {
        GeometryReader { proxy in
            let inner = WindowTabGroupShellShape.innerRect(in: CGRect(origin: .zero, size: proxy.size), tabBarHeight: strip.frame.height)
            let outer = WindowTabGroupOuterShape(activeWindowCornerRadius: strip.activeWindowCornerRadius)
            ZStack(alignment: .top) {
                MarketingMeasuredTabGroupFrameView(strip: strip, groupSize: proxy.size)
                MarketingAppWindow(kind: kind, title: title, cornerRadius: strip.activeWindowCornerRadius)
                    .frame(width: inner.width, height: inner.height)
                    .offset(y: inner.minY)
                WindowTabStripView(strip: strip)
                    .frame(height: strip.frame.height)
            }
            .clipShape(outer)
        }
    }
}

/// The focused window's border, drawn outside its frame as WinMuxX does.
struct MarketingBorder: ViewModifier {
    var isFocused: Bool
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                        .stroke(Color(nsColor: winMuxAccentColor), lineWidth: 4)
                        .padding(-4)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }
}

extension View {
    func marketingWindow(focused: Bool = false, cornerRadius: CGFloat = 16) -> some View {
        modifier(MarketingBorder(isFocused: focused, cornerRadius: cornerRadius))
    }
}

/// A desktop drawn in code: a soft gradient, not a captured wallpaper.
struct MarketingDesktop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.30), Color(red: 0.24, green: 0.14, blue: 0.40),
                                    Color(red: 0.08, green: 0.22, blue: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.55, green: 0.35, blue: 0.85).opacity(0.45), .clear], center: UnitPoint(x: 0.75, y: 0.2),
                           startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color(red: 0.2, green: 0.6, blue: 0.85).opacity(0.35), .clear], center: UnitPoint(x: 0.2, y: 0.9),
                           startRadius: 0, endRadius: 600)
        }
    }
}

/// The macOS menu bar across the top of a scene.
struct MarketingMenuBar: View {
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "apple.logo").font(.system(size: 14, weight: .semibold))
            Text("Finder").fontWeight(.semibold)
            Text("File"); Text("Edit"); Text("View"); Text("Go"); Text("Window"); Text("Help")
            Spacer()
            Image(systemName: "square.grid.2x2")
            Text("Sat 5 Sep  10:00")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 16)
        .frame(height: 26)
        .background(Color.black.opacity(0.18))
    }
}
