import AppKit
import SwiftUI

/// The tab bar of a Tabbed workspace: one browser-style tab per tiled window, in tree order.
struct WorkspaceTabBarModel: Equatable, Identifiable {
    let workspaceName: String
    /// AppKit screen coordinates of the bar, above the area the windows use.
    let frame: CGRect
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
        let bar = Rect(topLeftX: rect.topLeftX, topLeftY: rect.topLeftY, width: rect.width,
                       height: min(resolvedWindowTabBarHeight(), rect.height))
        models.append(WorkspaceTabBarModel(workspaceName: workspace.name, frame: bar.toAppKitScreenRect.alignedToBackingPixels(), tabs: tabs))
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
        if current?.tabs != model.tabs || current?.workspaceName != model.workspaceName {
            hostingView.rootView = AnyView(WorkspaceTabBarView(model: model))
        }
        if current?.frame != model.frame { setWindowTabChromePanelFrame(model.frame, on: self) }
        current = model
        if !isVisible { orderFrontRegardless() }
    }
}

/// Tabs share the bar's width up to a comfortable maximum and scroll when there are many.
struct WorkspaceTabBarView: View {
    let model: WorkspaceTabBarModel
    @State private var hovered: UInt32?
    private let spacing = windowTabStripTabSpacing
    private let padding: CGFloat = 6

    var body: some View {
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
        .background { OverlaySurface(cornerRadius: windowTabStripCornerRadius) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace tabs")
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
