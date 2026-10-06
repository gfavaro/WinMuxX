import SwiftUI

struct SettingsGapPreviewValues: Equatable {
    let horizontal: Int
    let vertical: Int
    let left: Int
    let right: Int
    let top: Int
    let bottom: Int

    /// A fixed 800 x 500 point display keeps all six gaps on the same scale.
    func frames(in size: CGSize) -> [CGRect] {
        let scale = min(size.width / 800, size.height / 500)
        let origin = CGPoint(x: (size.width - 800 * scale) / 2, y: (size.height - 500 * scale) / 2)
        let x = CGFloat(max(0, left)) * scale
        let y = CGFloat(max(0, top)) * scale
        let availableWidth = max(0, 800 * scale - x - CGFloat(max(0, right)) * scale)
        let availableHeight = max(0, 500 * scale - y - CGFloat(max(0, bottom)) * scale)
        let gapX = min(CGFloat(max(0, horizontal)) * scale, availableWidth)
        let gapY = min(CGFloat(max(0, vertical)) * scale, availableHeight)
        let width = (availableWidth - gapX) / 2
        let height = (availableHeight - gapY) / 2
        return (0..<4).map { index in
            CGRect(x: origin.x + x + CGFloat(index % 2) * (width + gapX),
                y: origin.y + y + CGFloat(index / 2) * (height + gapY), width: width, height: height)
        }
    }
}

struct SettingsGapPreview: View {
    let values: SettingsGapPreviewValues
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spacing preview").font(.headline)
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor))
                    ForEach(Array(values.frames(in: geometry.size).enumerated()), id: \.offset) { _, frame in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.accentColor.opacity(0.16))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(contrast == .increased ? 1 : 0.6), lineWidth: 1))
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: values)
            }
            .aspectRatio(1.6, contentMode: .fit)
            .frame(maxHeight: 220)
            .accessibilityHidden(true)
            SettingsDescription("Preview of the default spacing. Changes apply to your windows when you finish adjusting a slider.")
        }
    }
}
