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
        debugLog(.focus, "WindowTabGroupVisualPanel.update id=\(String(describing: identifier?.rawValue)) frame=\(panelFrame)")
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

extension NSPanelHud {
    /// Shared setup for non-activating, transparent tab chrome panels hosting SwiftUI content.
    func configureWindowTabChromePanel(identifier: String, hostingView: NSView) {
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        hasShadow = false
        isFloatingPanel = false
        isExcludedFromWindowsMenu = true
        // `.transient` lets the system hide tab chrome during Mission Control instead of showing it as a window.
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
        backgroundColor = .clear
        applyWinMuxLayer(.windowChrome)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }
}
