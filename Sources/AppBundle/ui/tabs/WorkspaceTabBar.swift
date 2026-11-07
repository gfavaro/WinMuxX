import AppKit
import SwiftUI

/// The tab bar of a Tabbed workspace: one browser-style tab per tiled window, in tree order.
struct WorkspaceTabBarModel: Equatable, Identifiable {
    let workspaceName: String
    /// AppKit screen coordinates of the bar and the window area under it together. The panel
    /// fills all of it behind the window, so the window's rounded corners show the bar's
    /// surface instead of the desktop and the two read as one piece.
    let frame: CGRect
    let barHeight: CGFloat
    let activeWindowId: UInt32
    let tabs: [WindowTabItemViewModel]
    var id: String { workspaceName }
}

extension Workspace {
    /// WinMuxX fullscreen, of a window or of a tab group's tab, which `layoutWorkspace` lays out
    /// before any arrangement: no bar is reserved then, so none may cover the window.
    @MainActor var presentsManagedFullscreen: Bool {
        rootTilingContainer.allTabbedContainersRecursive.contains(where: \.hasFullscreenTab)
            || rootTilingContainer.mostRecentWindowRecursive?.isFullscreen == true
    }
}

/// The bars for the visible Tabbed workspaces, with the windows each one lists, or nil when the
/// refresh was cancelled while titles were fetched, so a stale bar is never published.
@MainActor
func buildWorkspaceTabBarModels() async -> [WorkspaceTabBarModel]? {
    guard TrayMenuModel.shared.isEnabled else { return [] }
    var models: [WorkspaceTabBarModel] = []
    for workspace in Workspace.all where workspace.isVisible && workspace.arrangement == .tabbed
        && !shouldSuppressChromeForFullscreenContent(on: workspace.workspaceMonitor) && !workspace.presentsManagedFullscreen
    {
        let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
        guard let active = workspace.rootTilingContainer.mostRecentWindowRecursive, !windows.isEmpty else { continue }
        let tabs = await makeWindowTabChromeTabs(windows: windows, activeWindowId: active.windowId)
            .map { $0.legacyTabItem(workspaceName: workspace.name) }
        if Task.isCancelled { return nil }
        guard workspace.isVisible, workspace.arrangement == .tabbed, !workspace.presentsManagedFullscreen else { continue }
        let rect = workspaceTilingRect(workspace)
        models.append(WorkspaceTabBarModel(workspaceName: workspace.name, frame: rect.toAppKitScreenRect.alignedToBackingPixels(),
            barHeight: min(resolvedWindowTabBarHeight(), rect.height), activeWindowId: active.windowId, tabs: tabs))
    }
    return models
}

@MainActor
final class WorkspaceTabBarController {
    static let shared = WorkspaceTabBarController()
    private var panels: [String: WorkspaceTabBarPanel] = [:]

    private init() {}

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
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var current: WorkspaceTabBarModel?

    override init() {
        super.init()
        configureWindowTabChromePanel(identifier: "WinMux.workspaceTabBar", hostingView: hostingView)
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ model: WorkspaceTabBarModel) {
        if current?.tabs != model.tabs || current?.workspaceName != model.workspaceName || current?.barHeight != model.barHeight {
            hostingView.rootView = AnyView(WorkspaceTabBarView(model: model))
        }
        if current?.frame != model.frame { setWindowTabChromePanelFrame(model.frame, on: self) }
        // Just behind the window shown, reasserted on every refresh like the tab-group panels:
        // raising that window or another one changes the order outside this model.
        order(.below, relativeTo: Int(model.activeWindowId))
        // Never in front of the window: without it, the back of this level is the fallback.
        if !isVisible { order(.below, relativeTo: 0) }
        current = model
    }
}

/// Tabs share the bar's width up to a comfortable maximum and scroll when there are many.
struct WorkspaceTabBarView: View {
    let model: WorkspaceTabBarModel
    @State private var hovered: UInt32?
    private let spacing = windowTabStripTabSpacing
    private let padding: CGFloat = 6

    var body: some View {
        VStack(spacing: 0) {
            tabs.frame(height: model.barHeight)
            // The window covers this part; only its rounded corners show the surface.
            Color.clear.allowsHitTesting(false)
        }
        .background { OverlaySurface(cornerRadius: windowTabStripCornerRadius) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace tabs")
    }

    private var tabs: some View {
        GeometryReader { geometry in
            let height = geometry.size.height - 2 * padding
            let width = workspaceTabWidth(barWidth: geometry.size.width - 2 * padding, count: model.tabs.count, spacing: spacing)
            ScrollViewReader { proxy in ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(model.tabs) { tab in
                        WindowTabItemView(tab: tab, width: width, height: height, isDragSource: false, isHovered: hovered == tab.windowId)
                            .id(tab.windowId)
                            .onHover { inside in hovered = inside ? tab.windowId : (hovered == tab.windowId ? nil : hovered) }
                            .onTapGesture { focusWindowFromTabStripClick(tab.windowId, fallbackWorkspace: tab.workspaceName) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(tab.isActive ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { focusWindowFromTabStripClick(tab.windowId, fallbackWorkspace: tab.workspaceName) }
                    }
                }
                .padding(padding)
            }
            // A tab switched to while scrolled out of view comes into view, so one always shows as active.
            .onAppear { scrollToActive(proxy) }
            .onChange(of: model.tabs.first(where: \.isActive)?.windowId) { _ in scrollToActive(proxy) }
            }
        }
    }
}

extension WorkspaceTabBarView {
    fileprivate func scrollToActive(_ proxy: ScrollViewProxy) {
        guard let active = model.tabs.first(where: \.isActive)?.windowId else { return }
        proxy.scrollTo(active)
    }
}

/// Each tab's width when `count` tabs share `barWidth`, within the tab strip's widths.
func workspaceTabWidth(barWidth: CGFloat, count: Int, spacing: CGFloat) -> CGFloat {
    guard count > 0 else { return 0 }
    let shared = (barWidth - spacing * CGFloat(count - 1)) / CGFloat(count)
    return min(windowTabStripPreferredTabWidth, max(windowTabStripMinimumTabWidth, shared.rounded(.down)))
}
