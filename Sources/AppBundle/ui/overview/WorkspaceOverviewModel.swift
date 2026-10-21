import AppKit
import Common

struct WorkspaceOverviewWindow: Identifiable, Equatable {
    let id: UInt32
    let identity: ObjectIdentifier
    let pid: Int32
    let title: String
    let appName: String
    let icon: NSImage?
    /// Unit rectangle, top-left origin; nil means no trustworthy saved geometry.
    let frame: CGRect?
}

struct WorkspaceOverviewCard: Identifiable, Equatable {
    let id: WorkspaceId
    let name: String
    let title: String
    let monitor: MonitorViewportId
    let desktopSize: CGSize
    var windows: [WorkspaceOverviewWindow] // back to front
}

func workspaceOverviewIncludesWindow(standard: Bool, minimized: Bool, hiddenApp: Bool,
                                     fullscreen: Bool, popup: Bool, ownWindow: Bool, activeTab: Bool) -> Bool {
    standard && !minimized && !hiddenApp && !fullscreen && !popup && !ownWindow && activeTab
}

@MainActor
func workspaceOverviewIncludesWindow(_ window: Window) -> Bool {
    let standard = window.layoutReason == .standard
    let activeTab = window.nearestWindowTabGroup.map { !$0.usesWindowTabBehavior || $0.tabActiveWindow === window } ?? true
    return workspaceOverviewIncludesWindow(standard: standard,
        minimized: window.lastKnownNativeMinimized == true,
        hiddenApp: (window.app as? MacApp)?.nsApp.isHidden == true,
        fullscreen: window.lastKnownNativeFullscreen == true,
        popup: window.parent is MacosPopupWindowsContainer,
        ownWindow: window.app.pid == myPid, activeTab: activeTab)
}

@MainActor
func buildWorkspaceOverviewCards(project: WorkspaceProjectId, monitors: [Monitor]) -> [WorkspaceOverviewCard] {
    var icons: [Int32: NSImage] = [:]
    let validMonitors = Set(monitors.map { MonitorViewportId($0) })
    return orderedUserFacingWorkspaces(in: project).compactMap { workspace in
        let monitor = workspace.workspaceMonitor
        let key = MonitorViewportId(monitor)
        guard validMonitors.contains(key) else { return nil }
        let size = CGSize(width: monitor.width, height: monitor.height)
        let windows = workspace.allLeafWindowsRecursive.compactMap { window -> WorkspaceOverviewWindow? in
            guard workspaceOverviewIncludesWindow(window) else { return nil }
            let current = workspace.isVisible && !window.isHiddenInCorner
                ? window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
                : window.lastAppliedLayoutPhysicalRect
            let liveFrame = current.flatMap {
                normalizedWorkspacePreviewFrame(CGRect(origin: $0.topLeftCorner, size: $0.size),
                    origin: monitor.rect.topLeftCorner, desktopSize: size)
            }
            let frame = workspace.isVisible ? liveFrame ?? window.workspacePreviewFrame
                : window.workspacePreviewFrame ?? liveFrame
            if icons[window.app.pid] == nil { icons[window.app.pid] = (window.app as? MacApp)?.nsApp.icon }
            return WorkspaceOverviewWindow(id: window.windowId, identity: ObjectIdentifier(window), pid: window.app.pid,
                title: cachedWindowTitle(for: window) ?? window.app.name ?? "Window",
                appName: window.app.name ?? "Application", icon: icons[window.app.pid], frame: frame)
        }
        return WorkspaceOverviewCard(id: workspace.id, name: workspace.name,
            title: workspaceDisplayName(workspace.name), monitor: key, desktopSize: size, windows: windows)
    }
}

func workspaceOverviewHitWindow(_ windows: [WorkspaceOverviewWindow], at point: CGPoint) -> WorkspaceOverviewWindow? {
    windows.reversed().first { $0.frame?.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)).contains(point) == true }
}

@MainActor
final class WorkspaceOverviewDisplayModel: ObservableObject {
    var monitor: MonitorViewportId?
    @Published var cards: [WorkspaceOverviewCard] = []
    @Published var images: [WorkspaceId: CGImage] = [:]
    @Published var page = 0
    @Published var selection = 0
    @Published var selectedWindow: UInt32?
    var activate: ((WorkspaceId, UInt32?) -> Void)?
    var pageChanged: (() -> Void)?
    var dismiss: (() -> Void)?
    static let pageSize = 12
    var pageCount: Int { max(1, (cards.count + Self.pageSize - 1) / Self.pageSize) }
    var visibleCards: [WorkspaceOverviewCard] { Array(cards.dropFirst(page * Self.pageSize).prefix(Self.pageSize)) }
    var selectedCard: WorkspaceOverviewCard? { cards.indices.contains(selection) ? cards[selection] : nil }

    var accessibilitySelection: WorkspaceOverviewAccessibilitySelection? {
        guard let card = selectedCard else { return nil }
        if let window = card.windows.first(where: { $0.id == selectedWindow }),
           let frame = window.frame, frame.intersects(CGRect(x: 0, y: 0, width: 1, height: 1)) {
            return .window(window.id)
        }
        return .workspace(card.id)
    }

    func changePage(_ delta: Int) {
        let next = min(max(page + delta, 0), pageCount - 1)
        guard next != page else { return }
        page = next; selection = next * Self.pageSize; selectedWindow = nil; pageChanged?()
    }
    func moveSelection(_ delta: Int) {
        guard !cards.isEmpty else { return }
        selection = min(max(selection + delta, 0), cards.count - 1); selectedWindow = nil
        let next = selection / Self.pageSize
        if next != page { page = next; pageChanged?() }
    }
    func cycleWindow(backward: Bool) {
        guard let card = selectedCard, !card.windows.isEmpty else { selectedWindow = nil; return }
        let ids = card.windows.reversed().map(\.id)
        let index = selectedWindow.flatMap { ids.firstIndex(of: $0) }
        let next = index.map { ($0 + (backward ? ids.count - 1 : 1)) % ids.count } ?? (backward ? ids.count - 1 : 0)
        selectedWindow = ids[next]
    }
    func activateSelection() {
        if let card = selectedCard { activate?(card.id, selectedWindow) }
    }
}

enum WorkspaceOverviewAccessibilitySelection: Hashable {
    case workspace(WorkspaceId)
    case window(UInt32)
}
