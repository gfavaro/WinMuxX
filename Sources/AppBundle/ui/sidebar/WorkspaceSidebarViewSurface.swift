import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarView {
    var sidebarShape: some Shape {
        workspaceSidebarPanelShape(configuration: snapshot.configuration, visibleWidth: snapshot.visibleWidth)
    }

    @ViewBuilder
    func sidebarSurface<S: Shape>(in shape: S) -> some View {
        // The sidebar meets the display edge, so an outline around all four sides reads as a
        // second, lighter panel behind the content. Keep the material flat and use only the
        // trailing separator to define its boundary.
        let chrome = snapshot.configuration.chromeAppearance(systemScheme: colorScheme,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        if chrome.material != .solid {
            // The panel's NSVisualEffectView is the parent of this hosting
            // hierarchy. Keeping this layer clear lets AppKit apply vibrancy
            // to semantic SwiftUI foreground colors.
            Color.clear
                .overlay {
                    if let tint = chrome.veil,
                       snapshot.configuration.alwaysExpanded || snapshot.visibleWidth > snapshot.configuration.collapsedWidth + 8 {
                        WorkspaceSidebarFrostedVeil(tint: tint)
                    }
                }
                .clipShape(shape)
        } else {
            GlassSurface(
                shape: shape,
                hasBorder: false,
                style: snapshot.configuration.chromeStyle,
                solidColor: snapshot.configuration.resolvedSolidChromeColor,
            )
            // Keep the native glass backing layer inside the rounded trailing corners.
            .clipShape(shape)
        }
    }

    func sidebarSwipeCaptureOverlay(expansionProgress: CGFloat) -> some View {
        WorkspaceSidebarProjectSwipeScrollCapture(
            isEnabled: !snapshot.projects.isEmpty,
            onChanged: { horizontalTranslation, verticalTranslation in
                handleProjectSwipeChanged(
                    horizontalTranslation: horizontalTranslation,
                    verticalTranslation: verticalTranslation,
                    expansionProgress: expansionProgress,
                )
            },
            onEnded: { horizontalTranslation, verticalTranslation in
                handleProjectSwipeEnded(
                    horizontalTranslation: horizontalTranslation,
                    verticalTranslation: verticalTranslation,
                    expansionProgress: expansionProgress,
                )
            },
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

@MainActor
func workspaceSidebarPanelShape(configuration: WorkspaceSidebarConfiguration, visibleWidth: CGFloat) -> WorkspaceSidebarPanelShape {
    let centered = configuration.heightMode == .centered
    let progress = configuration.transparentExpansionProgress(visibleWidth: visibleWidth)
    let radius = centered ? systemWindowCornerRadius()
        : (progress < workspaceSidebarRowsRevealProgress ? 0 : workspaceSidebarPanelRightCornerRadius)
    return WorkspaceSidebarPanelShape(rightCornerRadius: radius, position: configuration.position, roundAllCorners: centered)
}

struct WorkspaceSidebarPanelShape: Shape {
    let rightCornerRadius: CGFloat
    var position: WorkspaceSidebarPosition = .left
    var roundAllCorners = false

    func path(in rect: CGRect) -> Path {
        if roundAllCorners {
            return RoundedRectangle(cornerRadius: rightCornerRadius, style: .continuous).path(in: rect)
        }
        let radius = min(rightCornerRadius, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        if position == .right {
            return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
        }
        return path
    }
}
