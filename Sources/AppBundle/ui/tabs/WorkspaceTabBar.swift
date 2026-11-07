import AppKit
import SwiftUI

/// The tab bar of a Tabbed workspace: one browser-style tab per tiled window, in tree order.
struct WorkspaceTabBarModel: Equatable, Identifiable {
    /// The tab group the bar belongs to.
    let id: ObjectIdentifier
    let workspaceName: String
    /// AppKit screen coordinates of the bar and the window area under it together. The panel
    /// fills all of it behind the window, so the window's rounded corners show the bar's
    /// surface instead of the desktop and the two read as one piece.
    let frame: CGRect
    let barHeight: CGFloat
    let activeWindowId: UInt32
    /// The bar itself, drawn by the tab strip view the original WinMux used for tab groups.
    let strip: WindowTabStripViewModel
    var tabs: [WindowTabItemViewModel] { strip.tabs }
}

extension Workspace {
    /// WinMuxX fullscreen, of a window or of a tab group's tab, which `layoutWorkspace` lays out
    /// before any arrangement: no bar is reserved then, so none may cover the window.
    @MainActor var presentsManagedFullscreen: Bool {
        rootTilingContainer.allTabbedContainersRecursive.contains(where: \.hasFullscreenTab)
            || rootTilingContainer.mostRecentWindowRecursive?.isFullscreen == true
    }
}

/// One bar per tab group of each visible Tabbed workspace, or nil when the refresh was cancelled
/// while titles were fetched, so a stale bar is never published.
@MainActor
func buildWorkspaceTabBarModels() async -> [WorkspaceTabBarModel]? {
    guard TrayMenuModel.shared.isEnabled else { return [] }
    var models: [WorkspaceTabBarModel] = []
    for workspace in Workspace.all where workspace.isVisible && workspace.arrangement == .tabbed
        && !shouldSuppressChromeForFullscreenContent(on: workspace.workspaceMonitor) && !workspace.presentsManagedFullscreen
    {
        workspace.syncTabbedGroups()
        // Groups folded into another's bar have no area of their own; their tabs are in that bar.
        for group in workspace.visibleTabbedLayout?.groups ?? [] where group.foldedInto == nil {
            let windows = group.barWindowIds.compactMap { Window.get(byId: $0) }
            guard let active = group.displayedWindow, let frame = group.lastFrame, !windows.isEmpty else { continue }
            let tabs = await makeWindowTabChromeTabs(windows: windows, activeWindowId: active.windowId)
                .map { $0.legacyTabItem(workspaceName: workspace.name) }
            if Task.isCancelled { return nil }
            guard workspace.isVisible, workspace.arrangement == .tabbed, !workspace.presentsManagedFullscreen,
                  workspace.tabbedGroups.contains(where: { $0 === group }) else { continue }
            let area = frame.toAppKitScreenRect.alignedToBackingPixels()
            let barHeight = min(resolvedWindowTabBarHeight(), area.height)
            let strip = WindowTabStripViewModel(id: ObjectIdentifier(group), workspaceName: workspace.name,
                frame: CGRect(x: area.minX, y: area.maxY - barHeight, width: area.width, height: barHeight),
                groupFrame: area, activeWindowId: active.windowId,
                activeWindowCornerRadius: windowTabGroupAppCornerRadius(activeWindowId: active.windowId), tabs: tabs,
                occludingFloatingWindowFrames: [], shownWindowIds: [active.windowId], headerHeight: barHeight, isWorkspaceTabs: true)
            models.append(WorkspaceTabBarModel(id: ObjectIdentifier(group), workspaceName: workspace.name, frame: area,
                barHeight: barHeight, activeWindowId: active.windowId, strip: strip))
        }
    }
    return models
}

@MainActor
final class WorkspaceTabBarController {
    static let shared = WorkspaceTabBarController()
    private var panels: [ObjectIdentifier: WorkspaceTabBarPanel] = [:]

    private init() {}

    /// Called with every tab chrome refresh, including when a drag starts or ends.
    func refreshMousePolicy() {
        for panel in panels.values { panel.updateMousePolicy() }
    }

    /// Mission Control hides the panels itself; the swipe preview and overview draw above them.
    func update(_ models: [WorkspaceTabBarModel]) {
        let ids = Set(models.map(\.id))
        for (id, panel) in panels where !ids.contains(id) {
            panel.orderOut(nil)
            panels.removeValue(forKey: id)
        }
        for model in models {
            let panel = panels[model.id] ?? WorkspaceTabBarPanel()
            panels[model.id] = panel
            panel.show(model)
        }
    }
}

@MainActor
final class WorkspaceTabBarPanel: NSPanelHud {
    private let hostingView = WorkspaceTabBarHostingView(rootView: AnyView(EmptyView()))
    private var current: WorkspaceTabBarModel?

    override init() {
        super.init()
        configureWindowTabChromePanel(identifier: "WinMux.workspaceTabBar", hostingView: hostingView)
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ model: WorkspaceTabBarModel) {
        if current?.strip != model.strip || current?.barHeight != model.barHeight {
            hostingView.rootView = AnyView(WorkspaceTabBarView(model: model))
        }
        updateMousePolicy()
        if current?.frame != model.frame { setWindowTabChromePanelFrame(model.frame, on: self) }
        // At the back of the window level, reasserted on every refresh: behind every window of a
        // side-by-side tab at once, while nothing but floating windows ever covers the bar.
        orderBack(nil)
        current = model
    }

    /// As the original strip panel: while a dragged tab is carried away, drops reach what lies beneath.
    func updateMousePolicy() {
        ignoresMouseEvents = currentlyManipulatedWithMouseWindowId != nil
            && shouldIgnoreWindowTabStripMouseEventsDuringDrag(detachOrigin: getCurrentMouseTabDetachOrigin())
    }
}

/// A tab responds to the first click, even while another app is active.
final class WorkspaceTabBarHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The original tab strip across the top, carrying its own surface; below it the same surface
/// sits behind the window, so the window's rounded corners show it.
struct WorkspaceTabBarView: View {
    let model: WorkspaceTabBarModel

    var body: some View {
        VStack(spacing: 0) {
            WindowTabStripView(strip: model.strip).frame(height: model.barHeight)
            OverlaySurface().allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace tabs")
    }
}
