import SwiftUI

/// The arrangement a pictogram card draws.
enum LayoutPictogram {
    case dwindle, master, tiles, tabbed, inherit
}

/// Main choices as pictogram cards, the way System Settings presents appearance options.
/// Each card is a button, so keyboard and VoiceOver users choose it like any other control.
struct SettingsPictogramPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        let pictogram: LayoutPictogram
    }

    let title: String
    let id: String
    @Binding var selection: Value
    let options: [Option]
    let help: String
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            HStack(alignment: .top, spacing: 10) {
                ForEach(options, id: \.value) { option in card(option) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityIdentifier(id)
            if !help.isEmpty { SettingsDescription(help) }
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
    }

    private func card(_ option: Option) -> some View {
        let selected = option.value == selection
        return Button {
            guard option.value != selection else { return }
            selection = option.value
            ShortcutSettingsModel.shared.activeSettingTitle = title
            onChange()
        } label: {
            VStack(spacing: 6) {
                LayoutPictogramView(kind: option.pictogram, selected: selected)
                    .frame(width: 76, height: 50)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 2 : 1))
                Text(option.title)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small drawing of a layout with three or four windows.
struct LayoutPictogramView: View {
    let kind: LayoutPictogram
    let selected: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                ForEach(Array(rects(in: size).enumerated()), id: \.offset) { index, rect in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(fill(index))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
                if kind == .inherit {
                    Text("Default").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: size.width, height: size.height)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(_ index: Int) -> Color {
        if kind == .inherit { return Color.primary.opacity(0.05) }
        return index == 0 && selected ? Color.accentColor.opacity(0.55) : Color.accentColor.opacity(selected ? 0.25 : 0.15)
    }

    /// Window rectangles for the layout, with a 3-point gap.
    func rects(in size: CGSize) -> [CGRect] {
        layoutPictogramRects(kind, in: size)
    }
}

func layoutPictogramRects(_ kind: LayoutPictogram, in size: CGSize, gap: CGFloat = 3) -> [CGRect] {
    let w = size.width, h = size.height
    let half = (w - gap) / 2
    switch kind {
        case .dwindle:
            let right = (h - gap) / 2
            let quarter = (half - gap) / 2
            return [CGRect(x: 0, y: 0, width: half, height: h),
                    CGRect(x: half + gap, y: 0, width: half, height: right),
                    CGRect(x: half + gap, y: right + gap, width: quarter, height: right),
                    CGRect(x: half + gap + quarter + gap, y: right + gap, width: quarter, height: right)]
        case .master:
            let main = (w - gap) * 0.6
            let side = w - main - gap
            let third = (h - 2 * gap) / 3
            return [CGRect(x: 0, y: 0, width: main, height: h)]
                + (0..<3).map { CGRect(x: main + gap, y: CGFloat($0) * (third + gap), width: side, height: third) }
        case .tiles:
            let row = (h - gap) / 2
            return [CGRect(x: 0, y: 0, width: half, height: row), CGRect(x: half + gap, y: 0, width: half, height: row),
                    CGRect(x: 0, y: row + gap, width: half, height: row), CGRect(x: half + gap, y: row + gap, width: half, height: row)]
        case .tabbed:
            let tab = (w - 2 * gap) / 3
            let strip: CGFloat = 8
            return [CGRect(x: 0, y: strip + gap, width: w, height: h - strip - gap)]
                + (0..<3).map { CGRect(x: CGFloat($0) * (tab + gap), y: 0, width: tab, height: strip) }
        case .inherit:
            return [CGRect(x: 0, y: 0, width: w, height: h)]
    }
}
