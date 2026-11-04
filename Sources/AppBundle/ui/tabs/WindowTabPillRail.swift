import AppKit
import SwiftUI

let windowTabPillHeight: CGFloat = 6
let windowTabPillSpacing: CGFloat = 4

/// A pill's width: the active window's is longest, other windows on screen (a strip's columns)
/// are medium, hidden ones short.
func windowTabPillWidth(isActive: Bool, isShown: Bool) -> CGFloat {
    isActive ? 22 : isShown ? 12 : 9
}

/// The pills' panel, centred on the group's top edge so half sits in the gap above it.
func windowTabPillPanelFrame(groupFrame: CGRect, tabs: [WindowTabItemViewModel], shownWindowIds: Set<UInt32>) -> CGRect {
    let widths = tabs.map { windowTabPillWidth(isActive: $0.isActive, isShown: shownWindowIds.contains($0.windowId)) }
    let width = widths.reduce(0, +) + windowTabPillSpacing * CGFloat(max(widths.count - 1, 0)) + 4
    let height = windowTabPillHeight + 4
    return CGRect(x: groupFrame.midX - width / 2, y: groupFrame.maxY - height / 2, width: width, height: height)
        .alignedToBackingPixels()
}

/// One pill per tab along the group's top edge. Resting the pointer there opens the hover bar
/// with the tabs and the window's actions.
struct WindowTabPillRail: View {
    @SidebarColors var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let tabs: [WindowTabItemViewModel]
    let shownWindowIds: Set<UInt32>

    var body: some View {
        HStack(spacing: windowTabPillSpacing) {
            ForEach(tabs) { tab in
                Capsule()
                    .fill(fill(for: tab))
                    .overlay(Capsule().stroke(Color.black.opacity(contrast == .increased ? 0.5 : 0.25), lineWidth: 0.5))
                    .frame(width: windowTabPillWidth(isActive: tab.isActive, isShown: shownWindowIds.contains(tab.windowId)),
                           height: windowTabPillHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : windowTabPillAnimation, value: tabs.map(\.isActive))
        .animation(reduceMotion ? nil : windowTabPillAnimation, value: shownWindowIds)
        .accessibilityHidden(true)
    }

    private func fill(for tab: WindowTabItemViewModel) -> Color {
        if tab.isActive { return .accentColor }
        return Color(nsColor: .systemGray).opacity(shownWindowIds.contains(tab.windowId) ? 0.95 : 0.7)
    }
}

/// A click-through panel holding a group's pills, straddling its top edge.
@MainActor
final class WindowTabPillPanel: NSPanelHud {
    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var current: (tabs: [WindowTabItemViewModel], shown: Set<UInt32>, frame: CGRect)?

    init(id: ObjectIdentifier) {
        super.init()
        configureWindowTabChromePanel(identifier: windowTabPillPanelPrefix + String(id.hashValue), hostingView: hostingView)
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(with strip: WindowTabStripViewModel) {
        let frame = windowTabPillPanelFrame(groupFrame: strip.groupFrame, tabs: strip.tabs, shownWindowIds: strip.shownWindowIds)
        if let current, current.tabs == strip.tabs, current.shown == strip.shownWindowIds, current.frame == frame, isVisible { return }
        if current?.tabs != strip.tabs || current?.shown != strip.shownWindowIds {
            hostingView.rootView = AnyView(WindowTabPillRail(tabs: strip.tabs, shownWindowIds: strip.shownWindowIds)
                .modifier(ChromeResolvedAppearance()))
        }
        current = (strip.tabs, strip.shownWindowIds, frame)
        setWindowTabChromePanelFrame(frame, on: self)
        applyWindowTabVisualStackingPolicy(for: strip, to: self)
    }
}
