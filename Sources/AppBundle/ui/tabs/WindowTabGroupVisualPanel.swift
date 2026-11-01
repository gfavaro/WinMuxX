import AppKit
import Common
import SwiftUI

@MainActor
final class WindowTabGroupVisualPanel: NSPanelHud {
    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    var currentContent: WindowTabGroupChromeContent?
    var currentPanelFrame: CGRect?

    init(id: ObjectIdentifier) {
        super.init()
        configureWindowTabChromePanel(identifier: windowTabVisualPanelPrefix + String(id.hashValue), hostingView: hostingView)
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(with strip: WindowTabStripViewModel) {
        let displayStrip = strip.alignedForWindowTabChrome()
        let panelFrame = displayStrip.groupFrame
        let nextContent = WindowTabGroupChromeContent(strip: displayStrip)
        guard shouldUpdate(content: nextContent, frame: panelFrame) else { return }
        if currentContent != nextContent {
            hostingView.rootView = AnyView(WindowTabGroupVisualView(
                strip: displayStrip,
            ))
            currentContent = nextContent
        }
        currentPanelFrame = panelFrame
        debugFocusLog("WindowTabGroupVisualPanel.update id=\(String(describing: identifier?.rawValue)) frame=\(panelFrame)")
        setWindowTabChromePanelFrame(panelFrame, on: self)
        ignoresMouseEvents = true
        applyWindowTabVisualStackingPolicy(for: displayStrip, to: self)
    }

    private func shouldUpdate(content: WindowTabGroupChromeContent, frame: CGRect) -> Bool {
        if currentContent == content, currentPanelFrame == frame, isVisible {
            ignoresMouseEvents = true
            return false
        }
        return true
    }
}
