import SwiftUI

struct WindowDropIntentOverlayView: View {
    let model: WindowDropIntentOverlayModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tint = WindowIntentPreviewPalette.tint(style: config.workspaceSidebar.chromeStyle,
                                                   solidColor: config.workspaceSidebar.resolvedSolidChromeColor)
        ZStack(alignment: .topLeading) {
            // A light wash, so the window being dropped on stays readable beneath.
            shape.fill(tint.opacity(0.06))
            shape.strokeBorder(tint.opacity(0.28), lineWidth: StrokeToken.hairline)
            if let zone = model.activeZone {
                landingGhost(zone, tint: tint)
            }
        }
        .clipShape(shape)
        .frame(width: model.targetFrame.width, height: model.targetFrame.height)
        .compositingGroup()
        .modifier(ChromeResolvedAppearance())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var cornerRadius: CGFloat {
        model.cornerRadius ?? min(max(min(model.targetFrame.width, model.targetFrame.height) * 0.018, 10), 14)
    }

    private var size: CGSize { CGSize(width: model.targetFrame.width, height: model.targetFrame.height) }

    /// Where the dragged window lands, drawn as a ghost of it: one shape that glides and reshapes
    /// from zone to zone, with only that zone's symbol.
    private func landingGhost(_ zone: WindowDropZone, tint: Color) -> some View {
        let unavailable = model.unavailableZones.contains(zone)
        let frame = landingFrame(for: zone).insetBy(dx: 8, dy: 8)
        let ghost = RoundedRectangle(cornerRadius: max(cornerRadius - 4, RadiusToken.row), style: .continuous)
        let color = unavailable ? Color.secondary : tint
        return ZStack(alignment: .top) {
            ghost.fill(color.opacity(unavailable ? 0.10 : 0.22))
            if zone == .tab, !unavailable {
                // Joining the tabs: the bar the window's tab joins, across the top.
                UnevenRoundedRectangle(topLeadingRadius: max(cornerRadius - 4, RadiusToken.row),
                                       topTrailingRadius: max(cornerRadius - 4, RadiusToken.row), style: .continuous)
                    .fill(color.opacity(0.35))
                    .frame(height: min(resolvedWindowTabBarHeight(), frame.height / 4))
            }
            // Only the outline glows: a glow behind the translucent fill would show through it.
            ghost.strokeBorder(color.opacity(unavailable ? 0.45 : 0.9),
                               style: StrokeStyle(lineWidth: StrokeToken.emphasis, dash: unavailable ? [6, 5] : []))
                .shadow(color: color.opacity(unavailable ? 0 : 0.45), radius: 10)
            VStack(spacing: 6) {
                Image(systemName: unavailable ? "nosign" : symbolName(for: zone))
                    .font(.system(size: iconSize(for: frame), weight: .semibold))
                if unavailable, let reason = model.unavailableReason {
                    Text(reason)
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: max(frame.width - 16, 60))
                }
            }
            .foregroundStyle(unavailable ? Color.secondary : tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .animation(reduceMotion ? nil : MotionToken.pill, value: zone)
    }

    /// The part of the target the window takes for each zone: a half for a split, all of it to
    /// swap or join the tabs.
    private func landingFrame(for zone: WindowDropZone) -> CGRect {
        let w = size.width, h = size.height
        return switch zone {
            case .left: CGRect(x: 0, y: 0, width: w / 2, height: h)
            case .right: CGRect(x: w / 2, y: 0, width: w / 2, height: h)
            case .top: CGRect(x: 0, y: 0, width: w, height: h / 2)
            case .bottom: CGRect(x: 0, y: h / 2, width: w, height: h / 2)
            case .middle, .tab: CGRect(origin: .zero, size: size)
        }
    }

    private func symbolName(for zone: WindowDropZone) -> String {
        switch zone {
            case .left:
                "arrow.left"
            case .right:
                "arrow.right"
            case .top:
                "arrow.up"
            case .bottom:
                "arrow.down"
            case .middle:
                "arrow.left.arrow.right"
            case .tab:
                "rectangle.3.group"
        }
    }

    private func iconSize(for frame: CGRect) -> CGFloat {
        min(max(min(frame.width, frame.height) * 0.22, 18), 44)
    }
}
